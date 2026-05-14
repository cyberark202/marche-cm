from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils import timezone
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError

from apps.accounts.models import UserRole
from apps.accounts.security import write_audit_log
from apps.notifications.realtime import broadcast_user_event
from apps.notifications.service import create_realtime_notification
from .models import SupportTicket, SupportTicketMessage, TicketStatus
from .serializers import SupportTicketMessageSerializer, SupportTicketSerializer


def _is_admin(user) -> bool:
    return bool(user and user.is_authenticated and (user.is_superuser or user.role == UserRole.GENERAL_ADMIN))


class SupportTicketViewSet(viewsets.ModelViewSet):
    serializer_class = SupportTicketSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = SupportTicket.objects.select_related("created_by", "assigned_to").prefetch_related("messages__author")

    def get_queryset(self):
        user = self.request.user
        if _is_admin(user):
            return self.queryset
        return self.queryset.filter(Q(created_by=user) | Q(assigned_to=user)).distinct()

    def perform_create(self, serializer):
        ticket = serializer.save(created_by=self.request.user)
        SupportTicketMessage.objects.create(
            ticket=ticket,
            author=self.request.user,
            body=ticket.description,
            is_internal=False,
        )
        self._notify_admins(
            title=f"Nouveau ticket #{ticket.id}",
            body=f"{self.request.user.username}: {ticket.subject}",
            payload={"ticket_id": ticket.id, "status": ticket.status},
        )
        self._broadcast_ticket_event(
            ticket=ticket,
            event_type="ticket_created",
            payload={"ticket_id": ticket.id, "created_by": ticket.created_by_id, "status": ticket.status},
            actor_id=self.request.user.id,
            include_admins=True,
        )
        write_audit_log(
            actor=self.request.user,
            action="Creation ticket support",
            action_key="support.ticket.create",
            metadata={"ticket_id": ticket.id},
        )

    def perform_update(self, serializer):
        user = self.request.user
        instance = self.get_object()
        if not _is_admin(user):
            raise PermissionDenied("Seuls les admins peuvent modifier ce ticket.")
        ticket = serializer.save()
        ticket.last_activity_at = timezone.now()
        ticket.save(update_fields=["last_activity_at", "updated_at"])
        if instance.created_by_id != user.id:
            create_realtime_notification(
                user=instance.created_by,
                title=f"Mise a jour ticket #{ticket.id}",
                body=f"Statut: {ticket.status}",
                payload={"ticket_id": ticket.id, "status": ticket.status},
            )
        self._broadcast_ticket_event(
            ticket=ticket,
            event_type="ticket_updated",
            payload={"ticket_id": ticket.id, "status": ticket.status, "assigned_to": ticket.assigned_to_id},
            actor_id=user.id,
            include_admins=True,
        )

    @decorators.action(detail=True, methods=["post"])
    def add_message(self, request, pk=None):
        ticket = self.get_object()
        user = request.user
        if not _is_admin(user) and user.id not in {ticket.created_by_id, ticket.assigned_to_id}:
            raise PermissionDenied("Acces refuse a ce ticket.")

        serializer = SupportTicketMessageSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        is_internal = bool(serializer.validated_data.get("is_internal"))
        if is_internal and not _is_admin(user):
            raise PermissionDenied("Note interne reservee aux admins.")

        message = SupportTicketMessage.objects.create(
            ticket=ticket,
            author=user,
            body=serializer.validated_data["body"],
            is_internal=is_internal,
        )
        ticket.last_activity_at = timezone.now()
        if ticket.status == TicketStatus.OPEN and _is_admin(user):
            ticket.status = TicketStatus.IN_PROGRESS
        ticket.save(update_fields=["last_activity_at", "status", "updated_at"])

        recipients = self._message_recipients(ticket=ticket, author_id=user.id)
        if not _is_admin(user):
            recipients.extend(self._extra_admin_recipients(author_id=user.id, existing=recipients))
        for recipient in recipients:
            create_realtime_notification(
                user=recipient,
                title=f"Nouveau message ticket #{ticket.id}",
                body=message.body[:180],
                payload={"ticket_id": ticket.id, "status": ticket.status},
            )
        self._broadcast_ticket_event(
            ticket=ticket,
            event_type="ticket_message_created",
            payload={"ticket_id": ticket.id, "message_id": message.id, "author_id": user.id},
            actor_id=user.id,
            include_admins=True,
        )
        return response.Response(
            SupportTicketMessageSerializer(message).data,
            status=status.HTTP_201_CREATED,
        )

    @decorators.action(detail=True, methods=["post"])
    def close(self, request, pk=None):
        ticket = self.get_object()
        user = request.user
        if not _is_admin(user) and ticket.created_by_id != user.id:
            raise PermissionDenied("Seul le createur ou un admin peut fermer le ticket.")
        if ticket.status == TicketStatus.CLOSED:
            return response.Response(SupportTicketSerializer(ticket).data, status=status.HTTP_200_OK)
        ticket.status = TicketStatus.CLOSED
        ticket.last_activity_at = timezone.now()
        ticket.save(update_fields=["status", "last_activity_at", "updated_at"])
        for recipient in self._message_recipients(ticket=ticket, author_id=user.id):
            create_realtime_notification(
                user=recipient,
                title=f"Ticket #{ticket.id} ferme",
                body=ticket.subject,
                payload={"ticket_id": ticket.id, "status": ticket.status},
            )
        self._broadcast_ticket_event(
            ticket=ticket,
            event_type="ticket_closed",
            payload={"ticket_id": ticket.id},
            actor_id=user.id,
            include_admins=True,
        )
        return response.Response(SupportTicketSerializer(ticket).data, status=status.HTTP_200_OK)

    @decorators.action(detail=True, methods=["post"])
    def assign(self, request, pk=None):
        if not _is_admin(request.user):
            raise PermissionDenied("Assignation reservee aux admins.")
        ticket = self.get_object()
        assigned_to_id = request.data.get("assigned_to")
        if not assigned_to_id:
            raise ValidationError({"assigned_to": "assigned_to est requis."})
        user_model = get_user_model()
        assigned = user_model.objects.filter(id=assigned_to_id).first()
        if not assigned:
            raise ValidationError({"assigned_to": "Utilisateur introuvable."})
        ticket.assigned_to = assigned
        ticket.status = TicketStatus.IN_PROGRESS if ticket.status == TicketStatus.OPEN else ticket.status
        ticket.last_activity_at = timezone.now()
        ticket.save(update_fields=["assigned_to", "status", "last_activity_at", "updated_at"])
        create_realtime_notification(
            user=ticket.created_by,
            title=f"Ticket #{ticket.id} assigne",
            body=f"Assigne a {assigned.username}",
            payload={"ticket_id": ticket.id, "assigned_to": assigned.id},
        )
        if assigned.id != request.user.id:
            create_realtime_notification(
                user=assigned,
                title=f"Ticket #{ticket.id} assigne",
                body=ticket.subject,
                payload={"ticket_id": ticket.id, "assigned_to": assigned.id},
            )
        self._broadcast_ticket_event(
            ticket=ticket,
            event_type="ticket_assigned",
            payload={"ticket_id": ticket.id, "assigned_to": assigned.id},
            actor_id=request.user.id,
            include_admins=True,
        )
        return response.Response(SupportTicketSerializer(ticket).data, status=status.HTTP_200_OK)

    def _notify_admins(self, *, title: str, body: str, payload: dict):
        admins = self._admins_queryset()
        for admin in admins:
            create_realtime_notification(user=admin, title=title, body=body, payload=payload)

    def _admins_queryset(self):
        user_model = get_user_model()
        return user_model.objects.filter(Q(role=UserRole.GENERAL_ADMIN) | Q(is_superuser=True), is_active=True).distinct()

    def _extra_admin_recipients(self, *, author_id: int, existing: list):
        existing_ids = {user.id for user in existing}
        recipients = []
        for admin in self._admins_queryset():
            if admin.id == author_id or admin.id in existing_ids:
                continue
            existing_ids.add(admin.id)
            recipients.append(admin)
        return recipients

    def _broadcast_ticket_event(
        self,
        *,
        ticket: SupportTicket,
        event_type: str,
        payload: dict,
        actor_id: int,
        include_admins: bool = False,
    ):
        recipients = self._message_recipients(ticket=ticket, author_id=actor_id)
        if include_admins:
            recipients.extend(self._extra_admin_recipients(author_id=actor_id, existing=recipients))
        seen_ids = set()
        for recipient in recipients:
            if recipient.id in seen_ids:
                continue
            seen_ids.add(recipient.id)
            broadcast_user_event(
                user_id=recipient.id,
                topic="support",
                event_type=event_type,
                payload=payload,
            )

    def _message_recipients(self, *, ticket: SupportTicket, author_id: int):
        candidates = [ticket.created_by]
        if ticket.assigned_to_id:
            candidates.append(ticket.assigned_to)
        recipients = []
        seen_ids = set()
        for user in candidates:
            if not user or user.id == author_id or user.id in seen_ids:
                continue
            seen_ids.add(user.id)
            recipients.append(user)
        return recipients
