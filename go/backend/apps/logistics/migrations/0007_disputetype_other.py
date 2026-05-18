from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("logistics", "0006_dispute_accused_party"),
    ]

    operations = [
        migrations.AlterField(
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
                    ("OTHER", "Autre (a preciser dans les details)"),
                ],
                default="QUALITY_DEFECT",
                max_length=30,
            ),
        ),
    ]
