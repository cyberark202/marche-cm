from django.conf import settings
from django.db import models


class NotificationCategory(models.TextChoices):
    ORDERS = "ORDERS", "Commandes"
    PAYMENTS = "PAYMENTS", "Paiements"
    WALLET = "WALLET", "Wallet"
    DELIVERIES = "DELIVERIES", "Livraisons"
    RENTALS = "RENTALS", "Locations"
    KYC = "KYC", "KYC"
    DISPUTES = "DISPUTES", "Litiges"
    PROMOTIONS = "PROMOTIONS", "Promotions"
    SECURITY = "SECURITY", "Securite"
    ADMIN = "ADMIN", "Administration"
    SYSTEM = "SYSTEM", "Systeme"


class NotificationPriority(models.TextChoices):
    LOW = "LOW", "Faible"
    NORMAL = "NORMAL", "Normale"
    HIGH = "HIGH", "Haute"
    CRITICAL = "CRITICAL", "Critique"


class Notification(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications")
    title = models.CharField(max_length=200)
    body = models.TextField()
    category = models.CharField(
        max_length=12, choices=NotificationCategory.choices, default=NotificationCategory.SYSTEM, db_index=True
    )
    priority = models.CharField(max_length=8, choices=NotificationPriority.choices, default=NotificationPriority.NORMAL)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class NotificationPreference(models.Model):
    """Préférences de notification (doc 10).

    Les notifications de sécurité ne peuvent jamais être désactivées : ce
    modèle ne porte donc que les canaux librement désactivables.
    """

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notification_preference"
    )
    promotions_enabled = models.BooleanField(default=True)
    push_enabled = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)


class PresenceSession(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="presence_sessions")
    connected_at = models.DateTimeField(auto_now_add=True)
    disconnected_at = models.DateTimeField(null=True, blank=True)
    is_active = models.BooleanField(default=True)

