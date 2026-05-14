from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("catalog", "0002_buyer_preferences"),
    ]

    operations = [
        migrations.AddField(
            model_name="product",
            name="available_qty",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="product",
            name="colors",
            field=models.CharField(blank=True, max_length=300),
        ),
        migrations.AddField(
            model_name="product",
            name="tags",
            field=models.CharField(blank=True, max_length=300),
        ),
        migrations.AddField(
            model_name="product",
            name="unit_price",
            field=models.DecimalField(blank=True, decimal_places=2, max_digits=12, null=True),
        ),
    ]
