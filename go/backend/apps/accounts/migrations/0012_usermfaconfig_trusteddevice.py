"""
Migration 0012 — TOTP MFA and Trusted Device support.

Security rationale:
  UserMFAConfig: Stores encrypted TOTP secret and PBKDF2-hashed backup codes
                 for strong multi-factor authentication (OWASP ASVS V2.8).
  TrustedDevice: Tracks per-user device fingerprints to detect token theft
                 and new-device logins (OWASP ASVS V3.5).
"""

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models

import apps.accounts.encrypted_fields


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0011_hash_otp_challenge_code"),
    ]

    operations = [
        migrations.CreateModel(
            name="UserMFAConfig",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("totp_secret", apps.accounts.encrypted_fields.EncryptedTextField(blank=True, default="")),
                ("totp_enabled", models.BooleanField(default=False)),
                ("backup_code_hashes", models.JSONField(blank=True, default=list)),
                ("totp_enrolled_at", models.DateTimeField(blank=True, null=True)),
                ("last_used_step", models.BigIntegerField(default=0)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="mfa_config",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"verbose_name": "MFA Configuration"},
        ),
        migrations.CreateModel(
            name="TrustedDevice",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("device_fingerprint", models.CharField(db_index=True, max_length=64)),
                ("user_agent_hash", models.CharField(blank=True, max_length=64)),
                ("ip_address_last", models.GenericIPAddressField(blank=True, null=True)),
                ("is_trusted", models.BooleanField(default=False)),
                ("trust_granted_at", models.DateTimeField(blank=True, null=True)),
                ("first_seen_at", models.DateTimeField(auto_now_add=True)),
                ("last_seen_at", models.DateTimeField(auto_now=True)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="trusted_devices",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"ordering": ["-last_seen_at"]},
        ),
        migrations.AddConstraint(
            model_name="trusteddevice",
            constraint=models.UniqueConstraint(
                fields=["user", "device_fingerprint"],
                name="uniq_user_device_fingerprint",
            ),
        ),
    ]
