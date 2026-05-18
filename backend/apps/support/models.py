from django.conf import settings
from django.db import models


class TicketStatus(models.TextChoices):
    OPEN = "OPEN", "Ouvert"
    IN_PROGRESS = "IN_PROGRESS", "En cours"
    RESOLVED = "RESOLVED", "Resolu"
    CLOSED = "CLOSED", "Ferme"


class TicketPriority(models.TextChoices):
    LOW = "LOW", "Bas"
    MEDIUM = "MEDIUM", "Moyen"
    HIGH = "HIGH", "Eleve"
    URGENT = "URGENT", "Urgent"


class SupportTicket(models.Model):
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="support_tickets")
    assigned_to = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="assigned_support_tickets",
    )
    subject = models.CharField(max_length=180)
    description = models.TextField()
    category = models.CharField(max_length=40, default="GENERAL")
    status = models.CharField(max_length=20, choices=TicketStatus.choices, default=TicketStatus.OPEN)
    priority = models.CharField(max_length=10, choices=TicketPriority.choices, default=TicketPriority.MEDIUM)
    last_activity_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-updated_at"]


class SupportTicketMessage(models.Model):
    ticket = models.ForeignKey(SupportTicket, on_delete=models.CASCADE, related_name="messages")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="support_ticket_messages")
    body = models.TextField()
    is_internal = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
