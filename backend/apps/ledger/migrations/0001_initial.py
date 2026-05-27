import uuid
import decimal
import django.core.validators
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="LedgerAccount",
            fields=[
                ("id", models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, serialize=False)),
                ("account_type", models.CharField(
                    max_length=12,
                    choices=[
                        ("ASSET", "Actif"),
                        ("LIABILITY", "Passif"),
                        ("EQUITY", "Capitaux propres"),
                        ("REVENUE", "Produits"),
                        ("EXPENSE", "Charges"),
                    ],
                )),
                ("sub_type", models.CharField(
                    max_length=24,
                    choices=[
                        ("USER_WALLET", "Wallet utilisateur"),
                        ("ESCROW_HOLD", "Séquestre escrow"),
                        ("PROVIDER_FLOAT", "Float fournisseur paiement"),
                        ("PLATFORM_REVENUE", "Revenus plateforme"),
                        ("PLATFORM_LIABILITY", "Dettes plateforme"),
                        ("PAYOUT_CLEARING", "Compensation payout"),
                        ("DISPUTE_RESERVE", "Réserve litige"),
                        ("SYSTEM_SUSPENSE", "Compte de suspens"),
                    ],
                )),
                ("owner", models.ForeignKey(
                    blank=True,
                    null=True,
                    on_delete=django.db.models.deletion.PROTECT,
                    related_name="ledger_accounts",
                    to=settings.AUTH_USER_MODEL,
                )),
                ("currency", models.CharField(default="XAF", max_length=3)),
                ("description", models.CharField(blank=True, max_length=200)),
                ("is_active", models.BooleanField(default=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={},
        ),
        migrations.CreateModel(
            name="LedgerTransaction",
            fields=[
                ("id", models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, serialize=False)),
                ("transaction_type", models.CharField(
                    db_index=True,
                    max_length=24,
                    choices=[
                        ("TOPUP", "Dépôt"),
                        ("WITHDRAWAL", "Retrait"),
                        ("ORDER_PAYMENT", "Paiement commande"),
                        ("ESCROW_LOCK", "Verrouillage escrow"),
                        ("ESCROW_RELEASE", "Libération escrow"),
                        ("ESCROW_REFUND", "Remboursement escrow"),
                        ("ESCROW_FREEZE", "Gel escrow"),
                        ("PAYOUT", "Payout vendeur"),
                        ("COMMISSION", "Commission plateforme"),
                        ("DISPUTE_FREEZE", "Gel litige"),
                        ("DISPUTE_RESOLUTION", "Résolution litige"),
                        ("REFUND", "Remboursement"),
                        ("ADJUSTMENT", "Ajustement"),
                        ("TRANSFER", "Transfert interne"),
                    ],
                )),
                ("idempotency_key", models.CharField(max_length=120, unique=True)),
                ("reference", models.CharField(blank=True, max_length=160)),
                ("description", models.CharField(blank=True, max_length=500)),
                ("currency", models.CharField(default="XAF", max_length=3)),
                ("total_amount", models.DecimalField(
                    decimal_places=2,
                    max_digits=14,
                    validators=[django.core.validators.MinValueValidator(decimal.Decimal("0.01"))],
                )),
                ("initiated_by", models.ForeignKey(
                    blank=True,
                    null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name="initiated_ledger_transactions",
                    to=settings.AUTH_USER_MODEL,
                )),
                ("correlation_id", models.CharField(blank=True, db_index=True, max_length=80)),
                ("metadata", models.JSONField(blank=True, default=dict)),
                ("posted_at", models.DateTimeField(auto_now_add=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={
                "ordering": ["-posted_at"],
            },
        ),
        migrations.CreateModel(
            name="LedgerEntry",
            fields=[
                ("id", models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, serialize=False)),
                ("transaction", models.ForeignKey(
                    on_delete=django.db.models.deletion.PROTECT,
                    related_name="entries",
                    to="ledger.ledgertransaction",
                )),
                ("account", models.ForeignKey(
                    on_delete=django.db.models.deletion.PROTECT,
                    related_name="entries",
                    to="ledger.ledgeraccount",
                )),
                ("direction", models.CharField(
                    max_length=8,
                    choices=[
                        ("DEBIT", "Débit"),
                        ("CREDIT", "Crédit"),
                    ],
                )),
                ("amount", models.DecimalField(
                    decimal_places=2,
                    max_digits=14,
                    validators=[django.core.validators.MinValueValidator(decimal.Decimal("0.01"))],
                )),
                ("running_balance", models.DecimalField(
                    decimal_places=2,
                    max_digits=14,
                    help_text="Balance of account AFTER this entry",
                )),
                ("description", models.CharField(blank=True, max_length=300)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={
                "ordering": ["created_at"],
            },
        ),
        # Indexes for LedgerAccount
        migrations.AddIndex(
            model_name="ledgeraccount",
            index=models.Index(fields=["sub_type", "owner"], name="idx_ledger_account_subtype_owner"),
        ),
        migrations.AddIndex(
            model_name="ledgeraccount",
            index=models.Index(fields=["account_type", "is_active"], name="idx_ledger_account_type_active"),
        ),
        # Constraint for LedgerAccount
        migrations.AddConstraint(
            model_name="ledgeraccount",
            constraint=models.UniqueConstraint(
                fields=["sub_type", "owner"],
                condition=models.Q(owner__isnull=False),
                name="uniq_ledger_account_user",
            ),
        ),
        # Indexes for LedgerTransaction
        migrations.AddIndex(
            model_name="ledgertransaction",
            index=models.Index(fields=["transaction_type", "posted_at"], name="idx_ledger_tx_type_date"),
        ),
        migrations.AddIndex(
            model_name="ledgertransaction",
            index=models.Index(fields=["idempotency_key"], name="idx_ledger_tx_idempotency"),
        ),
        # Indexes for LedgerEntry
        migrations.AddIndex(
            model_name="ledgerentry",
            index=models.Index(fields=["account", "created_at"], name="idx_ledger_entry_account_date"),
        ),
        migrations.AddIndex(
            model_name="ledgerentry",
            index=models.Index(fields=["transaction"], name="idx_ledger_entry_tx"),
        ),
    ]
