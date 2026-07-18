"""Jeu de données de démonstration pour les tests locaux.

Complète `seed_default_users` (comptes) avec des données réelles permettant de
piloter les 4 apps en local :
  * profils enrichis (téléphone, ville, coordonnées GPS, KYC) ;
  * catégories + produits actifs (feed / catalogue / boutique) ;
  * wallets crédités via le service comptable (invariants + ledger respectés) ;
  * une conversation de démo (messagerie temps réel).

Idempotent : ré-exécutable sans dupliquer (get_or_create + clés d'idempotence
sur les crédits wallet). N'insère JAMAIS de commande/escrow fabriqués : une fois
l'acheteur crédité et les produits en place, le checkout réel de l'app génère
commandes, séquestres et missions livreur en respectant la logique métier.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.db import transaction

from apps.accounts.models import UserRole
from apps.catalog.models import Product, ProductCategory
from apps.chat.models import ChatRoom, Message, MessageType
from apps.wallets.models import LedgerEntryType
from apps.wallets.services import WalletAccountingService

User = get_user_model()

_PROFILES = {
    "admin_general": ("+237600000001", "Douala", Decimal("4.0511"), Decimal("9.7679")),
    "supplier_demo": ("+237600000002", "Douala", Decimal("4.0611"), Decimal("9.7079")),
    "vendeur_demo": ("+237600000003", "Douala", Decimal("4.0411"), Decimal("9.7879")),
    "transit_demo": ("+237600000004", "Douala", Decimal("4.0711"), Decimal("9.7379")),
    "buyer_demo": ("+237600000005", "Yaoundé", Decimal("3.8480"), Decimal("11.5021")),
}

_CATEGORIES = ["Électronique", "Alimentation", "Mode & Textile", "Maison & Cuisine"]

_PRODUCTS = [
    ("vendeur_demo", "Smartphone X10 64Go", "NovaTech", "Électronique", 145000, 40, "0.35", "smartphone,android"),
    ("vendeur_demo", "Casque Bluetooth Pro", "SoundMax", "Électronique", 25000, 60, "0.25", "audio,casque"),
    ("vendeur_demo", "Blender 1.5L", "CuisinePro", "Maison & Cuisine", 22000, 35, "2.1", "cuisine,mixeur"),
    ("vendeur_demo", "Lot 6 assiettes", "TableChic", "Maison & Cuisine", 9000, 90, "3.0", "vaisselle,maison"),
    ("supplier_demo", "Sac de riz 25kg", "Grenier", "Alimentation", 18500, 120, "25.0", "riz,alimentation"),
    ("supplier_demo", "Huile végétale 5L", "OliaCM", "Alimentation", 6500, 200, "4.6", "huile,cuisine"),
    ("supplier_demo", "Chemise wax homme", "WaxHouse", "Mode & Textile", 12000, 80, "0.4", "wax,homme"),
    ("supplier_demo", "Robe pagne femme", "WaxHouse", "Mode & Textile", 15000, 70, "0.5", "pagne,femme"),
]

_FUNDING = {
    "buyer_demo": 5_000_000,
    "vendeur_demo": 150_000,
    "supplier_demo": 150_000,
    "transit_demo": 80_000,
}


class Command(BaseCommand):
    help = "Peuple la base locale avec des données de démo (users, produits, wallets, chat)."

    @transaction.atomic
    def handle(self, *args, **options):
        call_command("seed_default_users")
        users = {u.username: u for u in User.objects.filter(username__in=_PROFILES)}

        self._enrich_profiles(users)
        categories = self._seed_categories()
        self._seed_products(users, categories)
        self._fund_wallets(users)
        self._seed_chat(users)

        self.stdout.write(self.style.SUCCESS(
            "\nSeed de démo terminé. Mot de passe commun : ChangeMe123!\n"
            "Comptes : admin_general (admin) · vendeur_demo / supplier_demo (vendeurs) · "
            "transit_demo (livreur) · buyer_demo (acheteur).\n"
            f"Produits actifs : {Product.objects.filter(is_active=True).count()} · "
            f"Acheteur crédité : 5 000 000 XAF (checkout réel prêt)."
        ))

    def _enrich_profiles(self, users):
        for username, (phone, city, lat, lng) in _PROFILES.items():
            user = users.get(username)
            if user is None:
                continue
            user.phone_number = phone
            user.country_code = "CM"
            user.city = city
            user.location_label = f"{city}, Cameroun"
            user.location_latitude = lat
            user.location_longitude = lng
            user.kyc_level = 2
            if user.role != UserRole.BUYER:
                user.is_verified = True
            user.save()
        self.stdout.write(self.style.SUCCESS("Profils enrichis (téléphone, GPS, KYC)."))

    def _seed_categories(self):
        categories = {}
        for name in _CATEGORIES:
            categories[name], _ = ProductCategory.objects.get_or_create(name=name)
        return categories

    def _seed_products(self, users, categories):
        created = 0
        for seller_username, title, brand, cat, price, qty, weight, tags in _PRODUCTS:
            seller = users.get(seller_username)
            if seller is None:
                continue
            unit_price = Decimal(price)
            _, was_created = Product.objects.get_or_create(
                seller=seller,
                title=title,
                defaults={
                    "description": f"{title} — produit de démonstration ({brand}).",
                    "brand": brand,
                    "category": categories.get(cat),
                    "unit_price": unit_price,
                    "available_qty": qty,
                    "price_for_min_qty": unit_price,
                    "price_for_max_qty": unit_price,
                    "min_order_qty": 1,
                    "max_order_qty": qty,
                    "weight_kg": Decimal(weight),
                    "tags": tags,
                    "is_active": True,
                },
            )
            created += int(was_created)
        self.stdout.write(self.style.SUCCESS(f"Produits : {created} créés (total {Product.objects.count()})."))

    def _fund_wallets(self, users):
        for username, amount in _FUNDING.items():
            user = users.get(username)
            if user is None:
                continue
            wallet = WalletAccountingService.get_wallet_for_update(user=user)
            WalletAccountingService.credit_available(
                wallet=wallet,
                amount=Decimal(amount),
                entry_type=LedgerEntryType.DEPOSIT,
                reference=f"seed:funding:{username}",
                idempotency_key=f"seed-fund:{user.id}",
                metadata={"source": "seed_test_data"},
            )
        self.stdout.write(self.style.SUCCESS("Wallets crédités (via service comptable + ledger)."))

    def _seed_chat(self, users):
        buyer = users.get("buyer_demo")
        seller = users.get("vendeur_demo")
        if buyer is None or seller is None:
            return
        room, _ = ChatRoom.objects.get_or_create(name="Démo · Acheteur × Vendeur")
        room.participants.add(buyer, seller)
        if not room.messages.exists():
            Message.objects.create(room=room, sender=buyer, type=MessageType.TEXT,
                                   content="Bonjour, le Smartphone X10 est-il disponible ?")
            Message.objects.create(room=room, sender=seller, type=MessageType.TEXT,
                                   content="Oui, en stock. Vous pouvez commander depuis l'application.")
        self.stdout.write(self.style.SUCCESS("Conversation de démo créée."))
