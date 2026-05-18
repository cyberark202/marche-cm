from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("catalog", "0008_add_videolike_videocomment"),
    ]

    operations = [
        # Column already exists in production DB — register state only.
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.AddField(
                    model_name="product",
                    name="video_duration_seconds",
                    field=models.PositiveIntegerField(
                        default=0,
                        validators=[MinValueValidator(0), MaxValueValidator(180)],
                    ),
                ),
            ],
            database_operations=[],
        ),
    ]
