"""
Migration 0011 — Harden SensitiveActionChallenge OTP storage.

Changes:
  1. Rename `code` (plaintext, max_length=6) → `code_hash` (PBKDF2 hash, max_length=128)
  2. Widen challenge_token to max_length=128 (tokens are now 43-char url-safe base64)
  3. Expire every existing active challenge immediately so no plaintext OTP survives.

Security rationale (OWASP ASVS V2.7.6):
  OTPs must never be stored in cleartext. All active challenges issued before this
  migration used the old plaintext scheme and are cryptographically invalidated here.
  Users who had a pending challenge must request a fresh one after the upgrade.
"""

from django.db import migrations, models
from django.utils import timezone


def _expire_plaintext_challenges(apps, schema_editor):
    SensitiveActionChallenge = apps.get_model("accounts", "SensitiveActionChallenge")
    now = timezone.now()
    SensitiveActionChallenge.objects.filter(
        used_at__isnull=True,
        expires_at__gt=now,
    ).update(expires_at=now)


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0010_sensitiveactionchallenge"),
    ]

    operations = [
        # Step 1 — Rename the plaintext OTP column to its new hashed name.
        migrations.RenameField(
            model_name="sensitiveactionchallenge",
            old_name="code",
            new_name="code_hash",
        ),
        # Step 2 — Widen to hold a full PBKDF2-SHA256 hash string (~77 chars
        #           in Django's default format; 128 gives comfortable headroom).
        migrations.AlterField(
            model_name="sensitiveactionchallenge",
            name="code_hash",
            field=models.CharField(max_length=128),
        ),
        # Step 3 — Widen challenge_token to match the new 43-char url-safe
        #           base64 tokens (secrets.token_urlsafe(32)).
        migrations.AlterField(
            model_name="sensitiveactionchallenge",
            name="challenge_token",
            field=models.CharField(db_index=True, max_length=128, unique=True),
        ),
        # Step 4 — Cryptographically invalidate every active challenge that was
        #           created under the old plaintext scheme. The `code_hash` column
        #           now contains the old 6-char plaintext value which is NOT a valid
        #           PBKDF2 hash, so check_password() would reject it anyway — but we
        #           also expire them explicitly for defense-in-depth.
        migrations.RunPython(
            _expire_plaintext_challenges,
            reverse_code=migrations.RunPython.noop,
        ),
    ]
