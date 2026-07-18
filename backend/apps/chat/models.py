from django.conf import settings
from django.db import models


class ChatRoom(models.Model):
    name = models.CharField(max_length=150, blank=True)
    participants = models.ManyToManyField(settings.AUTH_USER_MODEL, related_name="chat_rooms")
    created_at = models.DateTimeField(auto_now_add=True)


class MessageType(models.TextChoices):
    TEXT = "TEXT", "Texte"
    IMAGE = "IMAGE", "Image"
    VIDEO = "VIDEO", "Video"
    DOCUMENT = "DOCUMENT", "Document"
    AUDIO = "AUDIO", "Note vocale"


class Message(models.Model):
    room = models.ForeignKey(ChatRoom, on_delete=models.CASCADE, related_name="messages")
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="sent_messages")
    type = models.CharField(max_length=10, choices=MessageType.choices, default=MessageType.TEXT)
    content = models.TextField(blank=True)
    file = models.FileField(upload_to="chat/", blank=True, null=True)
    # Reply-to (quote) — points at an earlier message in the SAME room. SET_NULL
    # so deleting/withholding the quoted message never cascades away replies.
    reply_to = models.ForeignKey(
        "self",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="replies",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        # Ordre anté-chronologique : la page 1 de l'API contient les messages
        # les PLUS RÉCENTS (ouverture de conversation « en bas » façon WhatsApp,
        # l'historique se charge en remontant). Avant : ASC → la page 1
        # renvoyait les 20 plus anciens et un fil long s'ouvrait sur son début.
        # -id départage les créations dans la même milliseconde (ordre stable).
        ordering = ["-created_at", "-id"]


class DeliveryState(models.TextChoices):
    SENT = "SENT", "Envoye"
    DELIVERED = "DELIVERED", "Livre"
    READ = "READ", "Lu"


class MessageReaction(models.Model):
    """Réaction emoji façon WhatsApp : une seule par utilisateur et par message
    (re-choisir le même emoji la retire, un autre la remplace)."""

    message = models.ForeignKey(Message, on_delete=models.CASCADE, related_name="reactions")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="message_reactions")
    emoji = models.CharField(max_length=8)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["message", "user"], name="uniq_message_reaction"),
        ]


class MessageReceipt(models.Model):
    message = models.ForeignKey(Message, on_delete=models.CASCADE, related_name="receipts")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="message_receipts")
    state = models.CharField(max_length=10, choices=DeliveryState.choices, default=DeliveryState.SENT)
    sent_at = models.DateTimeField(auto_now_add=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["message", "user"], name="uniq_message_receipt"),
        ]
