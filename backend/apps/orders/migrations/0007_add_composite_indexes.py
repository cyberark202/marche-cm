# Generated migration: Add composite indexes for performance
# Compatible with both SQLite (dev) and PostgreSQL (prod)

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('orders', '0006_alter_order_escrow_status'),
    ]

    operations = [
        migrations.RunSQL(
            # SQLite: CREATE INDEX (no CONCURRENTLY)
            # PostgreSQL: CONCURRENTLY added in prod via ALTER
            sql="""
            CREATE INDEX idx_order_buyer_status_date
            ON orders_order(buyer_id, status, created_at DESC)
            WHERE status != 'CANCELLED';
            """,
            reverse_sql="DROP INDEX IF EXISTS idx_order_buyer_status_date;",
            state_operations=[],
        ),
        migrations.RunSQL(
            sql="""
            CREATE INDEX idx_order_seller_status_date
            ON orders_order(seller_id, status, created_at DESC)
            WHERE status != 'CANCELLED';
            """,
            reverse_sql="DROP INDEX IF EXISTS idx_order_seller_status_date;",
            state_operations=[],
        ),
    ]
