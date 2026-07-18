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
    reply_to = models.ForeignKey(
        "self",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="replies",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
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
