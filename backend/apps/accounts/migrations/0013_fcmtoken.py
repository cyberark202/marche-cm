"""
Reconcile TrustedDevice constraints: migration 0012 added a named UniqueConstraint
but the model uses unique_together. This migration converts to unique_together so
the two representations stay in sync.
"""
from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0012_usermfaconfig_trusteddevice"),
    ]

    operations = [
        migrations.RemoveConstraint(
            model_name="trusteddevice",
            name="uniq_user_device_fingerprint",
        ),
        migrations.AlterUniqueTogether(
            name="trusteddevice",
            unique_together={("user", "device_fingerprint")},
        ),
    ]
