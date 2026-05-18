import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("logistics", "0004_transportprofile_pricing_and_shipment_mode"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        # --- Shipment: contest_deadline + DISPUTED status ---
        migrations.AddField(
            model_name="shipment",
            name="contest_deadline",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="shipment",
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
                default="PICKUP_PENDING",
                max_length=20,
            ),
        ),
        # --- ShipmentDispute: new fields ---
        migrations.AddField(
            model_name="shipmentdispute",
            name="dispute_type",
            field=models.CharField(
                choices=[
                    ("QUALITY_DEFECT", "Marchandise de mauvaise qualite"),
                    ("WRONG_QUANTITY", "Quantite incomplete"),
                    ("COUNTERFEIT", "Produit contrefait"),
                    ("FALSE_NON_RECEIPT", "Fausse declaration de non-reception"),
                    ("USED_THEN_DISPUTED", "Produit utilise puis conteste"),
                    ("DELIVERY_DELAY", "Retard de livraison"),
                    ("LOST_PARCEL", "Colis perdu"),
                    ("WRONG_RECIPIENT", "Livraison au mauvais destinataire"),
                    ("ESCROW_BLOCKED", "Fonds bloques trop longtemps"),
                    ("PREMATURE_RELEASE", "Liberation prematuree des fonds"),
                    ("WALLET_FROZEN", "Gel de wallet injustifie"),
                    ("DOUBLE_CHARGE", "Double debit Mobile Money"),
                    ("WITHDRAWAL_ERROR", "Erreur de retrait wallet"),
                    ("CHARGEBACK", "Chargeback bancaire"),
                    ("FAKE_DOCUMENTS", "Faux documents vendeur"),
                    ("UNJUST_SUSPENSION", "Suspension injustifiee"),
                    ("DAMAGED_GOODS", "Marchandise endommagee durant transport"),
                    ("INTERNAL_THEFT", "Vol interne"),
                    ("FALSE_TRACKING", "Fausse mise a jour de suivi"),
                    ("MISLEADING_AD", "Publicite trompeuse"),
                    ("FAKE_STATS", "Faux chiffres de visibilite campagne"),
                    ("DATA_BREACH", "Fuite de donnees KYC"),
                    ("UNAUTHORIZED_ACCESS", "Acces non autorise au compte"),
                    ("CATALOG_COPY", "Copie de catalogue"),
                    ("FAKE_REVIEWS", "Faux avis negatifs"),
                    ("MODERATION_BIAS", "Favoritisme dans la moderation"),
                    ("HISTORY_TAMPER", "Modification de l'historique"),
                    ("FINANCIAL_REGULATION", "Activite financiere non autorisee"),
                    ("TAX_COMPLIANCE", "Non-conformite fiscale"),
                    ("MULTI_ACTOR", "Responsabilite multi-acteurs indeterminee"),
                ],
                default="QUALITY_DEFECT",
                max_length=30,
            ),
        ),
        migrations.AlterField(
            model_name="shipmentdispute",
            name="status",
            field=models.CharField(
                choices=[
                    ("OPEN", "Ouvert"),
                    ("UNDER_REVIEW", "En traitement"),
                    ("INSPECTION_PENDING", "Inspection physique en cours"),
                    ("APPEAL_REQUESTED", "Appel en cours"),
                    ("RESOLVED", "Resolu"),
                    ("CLOSED_NO_ACTION", "Ferme sans action"),
                ],
                default="OPEN",
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="chat_integrity_hash",
            field=models.CharField(blank=True, max_length=64),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="inspection_required",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="inspection_requested_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="inspector_report",
            field=models.FileField(blank=True, null=True, upload_to="dispute-inspections/"),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="inspector_report_uploaded_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="guarantee_fund_activated",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="guarantee_fund_amount",
            field=models.DecimalField(blank=True, decimal_places=2, max_digits=12, null=True),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="guarantee_fund_activated_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="last_custody_holder",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="disputes_as_last_holder",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="appeal_requested",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="appeal_requested_by",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="appeal_requested_disputes",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="appeal_requested_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="appeal_reviewed_by",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="appeal_reviewed_disputes",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="appeal_decision",
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="appeal_resolved_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="escalation_count",
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="shipmentdispute",
            name="is_multi_actor",
            field=models.BooleanField(default=False),
        ),
        # --- CustodyEvent ---
        migrations.CreateModel(
            name="CustodyEvent",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False)),
                (
                    "shipment",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="custody_events",
                        to="logistics.shipment",
                    ),
                ),
                (
                    "actor",
                    models.ForeignKey(
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="logged_custody_events",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "event_type",
                    models.CharField(
                        choices=[
                            ("PICKUP", "Prise en charge par le transporteur"),
                            ("WAREHOUSE_IN", "Entree en entrepot"),
                            ("WAREHOUSE_OUT", "Sortie d'entrepot"),
                            ("HANDOVER", "Transfert de garde"),
                            ("OUT_FOR_DELIVERY", "Depart pour livraison"),
                            ("DELIVERED", "Remis au destinataire"),
                        ],
                        max_length=20,
                    ),
                ),
                ("photo", models.ImageField(blank=True, null=True, upload_to="custody-events/")),
                ("location", models.CharField(blank=True, max_length=250)),
                ("notes", models.CharField(blank=True, max_length=500)),
                ("integrity_hash", models.CharField(blank=True, db_index=True, max_length=64)),
                ("scanned_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={"ordering": ["scanned_at"]},
        ),
        # --- DisputeEvidence ---
        migrations.CreateModel(
            name="DisputeEvidence",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False)),
                (
                    "dispute",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="evidences",
                        to="logistics.shipmentdispute",
                    ),
                ),
                (
                    "uploaded_by",
                    models.ForeignKey(
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="uploaded_dispute_evidences",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                ("file", models.FileField(upload_to="dispute-evidences/")),
                (
                    "evidence_type",
                    models.CharField(
                        choices=[
                            ("PHOTO", "Photo"),
                            ("VIDEO", "Video"),
                            ("DOCUMENT", "Document"),
                            ("SCREENSHOT", "Capture d'ecran"),
                            ("INSPECTION_REPORT", "Rapport d'inspection"),
                        ],
                        default="DOCUMENT",
                        max_length=20,
                    ),
                ),
                ("description", models.CharField(blank=True, max_length=300)),
                ("file_integrity_hash", models.CharField(blank=True, db_index=True, max_length=64)),
                ("file_size_bytes", models.PositiveIntegerField(default=0)),
                ("uploaded_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={"ordering": ["uploaded_at"]},
        ),
    ]
