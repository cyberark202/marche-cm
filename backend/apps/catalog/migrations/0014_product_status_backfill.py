"""Backfill de la machine à états produit (docs 12/22).

Les produits désactivés avant l'introduction du statut étaient soit masqués
par le vendeur, soit soft-supprimés : les deux correspondent à ARCHIVED.
Les produits actifs restent PUBLISHED (défaut du champ).
"""
from django.db import migrations


def backfill_status(apps, schema_editor):
    Product = apps.get_model("catalog", "Product")
    Product.objects.filter(is_active=False).update(status="ARCHIVED")


def noop(apps, schema_editor):
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("catalog", "0013_product_status"),
    ]

    operations = [
        migrations.RunPython(backfill_status, noop),
    ]
