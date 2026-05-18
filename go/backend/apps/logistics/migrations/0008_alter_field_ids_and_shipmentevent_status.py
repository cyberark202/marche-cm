"""
Reconcile model state with DEFAULT_AUTO_FIELD=BigAutoField and updated
ShipmentEvent.status max_length. These are metadata-only changes on most
databases (PostgreSQL does not rewrite the table for max_length increases).
"""
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("logistics", "0007_disputetype_other"),
    ]

    operations = [
        migrations.AlterField(
            model_name="custodyevent",
            name="id",
            field=models.BigAutoField(
                auto_created=True,
                primary_key=True,
                serialize=False,
                verbose_name="ID",
            ),
        ),
        migrations.AlterField(
            model_name="disputeevidence",
            name="id",
            field=models.BigAutoField(
                auto_created=True,
                primary_key=True,
                serialize=False,
                verbose_name="ID",
            ),
        ),
        migrations.AlterField(
            model_name="shipmentevent",
            name="status",
            field=models.CharField(
                choices=[
                    ("PICKUP_PENDING", "En attente de collecte"),
                    ("IN_TRANSIT", "En transit"),
                    ("AT_CUSTOMS", "En douane"),
                    ("OUT_FOR_DELIVERY", "En cours de livraison"),
                    ("DELIVERED", "Livre"),
                    ("DISPUTED", "En litige"),
                    ("CANCELLED", "Annule"),
                ],
                max_length=20,
            ),
        ),
    ]
