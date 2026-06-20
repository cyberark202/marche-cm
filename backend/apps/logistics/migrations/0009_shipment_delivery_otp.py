from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("logistics", "0008_alter_field_ids_and_shipmentevent_status"),
    ]

    operations = [
        migrations.AddField(
            model_name="shipment",
            name="delivery_otp_hash",
            field=models.CharField(blank=True, max_length=128),
        ),
        migrations.AddField(
            model_name="shipment",
            name="delivery_otp_expires_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
