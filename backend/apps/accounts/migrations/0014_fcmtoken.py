from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0013_fcmtoken"),
    ]

    operations = [
        migrations.CreateModel(
            name="FCMToken",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("registration_id", models.TextField(unique=True)),
                (
                    "type",
                    models.CharField(
                        choices=[
                            ("android", "Android"),
                            ("ios", "iOS"),
                            ("web", "Web"),
                        ],
                        default="android",
                        max_length=10,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="fcm_tokens",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["-updated_at"],
            },
        ),
    ]
