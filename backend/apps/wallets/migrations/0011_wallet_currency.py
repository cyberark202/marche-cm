from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("wallets", "0010_idempotency_state_log_indexes"),
    ]

    operations = [
        migrations.AddField(
            model_name="wallet",
            name="currency",
            field=models.CharField(default="XAF", max_length=3),
        ),
    ]
