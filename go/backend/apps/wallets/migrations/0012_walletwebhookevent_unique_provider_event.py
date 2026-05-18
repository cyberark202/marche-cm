from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("wallets", "0011_wallet_currency"),
    ]

    operations = [
        migrations.AlterField(
            model_name="walletwebhookevent",
            name="event_id",
            field=models.CharField(max_length=120),
        ),
        migrations.AddConstraint(
            model_name="walletwebhookevent",
            constraint=models.UniqueConstraint(
                fields=["provider", "event_id"],
                name="uniq_webhookevent_provider_event_id",
            ),
        ),
    ]
