from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0014_fcmtoken"),
    ]

    operations = [
        migrations.CreateModel(
            name="DriverProfile",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                (
                    "vehicle_type",
                    models.CharField(
                        choices=[
                            ("MOTO", "Moto / Scooter"),
                            ("CAR", "Voiture"),
                            ("VAN", "Camionnette"),
                            ("TRUCK", "Camion"),
                            ("BICYCLE", "Vélo"),
                            ("FOOT", "À pied"),
                        ],
                        default="MOTO",
                        max_length=20,
                    ),
                ),
                ("license_number", models.CharField(blank=True, max_length=60)),
                ("rating", models.DecimalField(decimal_places=2, default=0, max_digits=3)),
                ("completed_deliveries", models.PositiveIntegerField(default=0)),
                ("is_approved", models.BooleanField(default=False)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "user",
                    models.OneToOneField(
                        limit_choices_to={"role": "DRIVER"},
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="driver_profile",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"ordering": ["-created_at"]},
        ),
    ]
