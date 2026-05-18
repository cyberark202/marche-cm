from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from apps.accounts.models import UserRole
from apps.logistics.models import TransportProfile


DEFAULT_PASSWORD = "ChangeMe123!"


class Command(BaseCommand):
    help = "Cree des comptes par defaut pour chaque type d'utilisateur."

    def add_arguments(self, parser):
        parser.add_argument(
            "--password",
            default=DEFAULT_PASSWORD,
            help="Mot de passe applique aux comptes crees (et optionnellement reset).",
        )
        parser.add_argument(
            "--reset-passwords",
            action="store_true",
            help="Reinitialise aussi le mot de passe des comptes deja existants.",
        )

    def handle(self, *args, **options):
        user_model = get_user_model()
        password = options["password"]
        reset_passwords = options["reset_passwords"]

        definitions = [
            {
                "username": "admin_general",
                "email": "admin@marche-cm.local",
                "first_name": "Admin",
                "last_name": "General",
                "role": UserRole.GENERAL_ADMIN,
                "is_staff": True,
                "is_superuser": True,
            },
            {
                "username": "supplier_demo",
                "email": "supplier@marche-cm.local",
                "first_name": "Compte",
                "last_name": "Fournisseur",
                "role": UserRole.SUPPLIER,
                "is_staff": False,
                "is_superuser": False,
            },
            {
                "username": "wholesaler_demo",
                "email": "wholesaler@marche-cm.local",
                "first_name": "Compte",
                "last_name": "Grossiste",
                "role": UserRole.WHOLESALER,
                "is_staff": False,
                "is_superuser": False,
            },
            {
                "username": "transit_demo",
                "email": "transit@marche-cm.local",
                "first_name": "Compte",
                "last_name": "Transitaire",
                "role": UserRole.TRANSIT_AGENT,
                "is_staff": False,
                "is_superuser": False,
            },
            {
                "username": "buyer_demo",
                "email": "buyer@marche-cm.local",
                "first_name": "Compte",
                "last_name": "Acheteur",
                "role": UserRole.BUYER,
                "is_staff": False,
                "is_superuser": False,
            },
        ]

        for definition in definitions:
            username = definition["username"]
            email = definition["email"]
            defaults = {
                "email": email,
                "first_name": definition["first_name"],
                "last_name": definition["last_name"],
                "role": definition["role"],
                "is_active": True,
                "is_verified": definition["role"] in {UserRole.GENERAL_ADMIN, UserRole.BUYER},
                "is_staff": definition["is_staff"],
                "is_superuser": definition["is_superuser"],
            }

            user, created = user_model.objects.get_or_create(
                username=username,
                defaults=defaults,
            )

            if created:
                user.set_password(password)
                user.save()
                self.stdout.write(self.style.SUCCESS(f"Cree: {username} ({definition['role']})"))
            else:
                changes = []
                for field, value in defaults.items():
                    if getattr(user, field) != value:
                        setattr(user, field, value)
                        changes.append(field)

                if reset_passwords:
                    user.set_password(password)
                    changes.append("password")

                if changes:
                    user.save()
                    self.stdout.write(self.style.WARNING(f"Mis a jour: {username} ({', '.join(changes)})"))
                else:
                    self.stdout.write(f"Inchange: {username}")

            if user.role == UserRole.TRANSIT_AGENT:
                profile, profile_created = TransportProfile.objects.get_or_create(
                    user=user,
                    defaults={
                        "company_name": f"Transit {user.username}",
                        "coverage_countries": user.country_code or "CM",
                        "air_price_per_kg": 3500,
                        "sea_price_per_kg": 1800,
                        "is_active": True,
                    },
                )
                if not profile_created:
                    fields = []
                    if profile.air_price_per_kg <= 0:
                        profile.air_price_per_kg = 3500
                        fields.append("air_price_per_kg")
                    if profile.sea_price_per_kg <= 0:
                        profile.sea_price_per_kg = 1800
                        fields.append("sea_price_per_kg")
                    if fields:
                        profile.save(update_fields=fields)
                        self.stdout.write(self.style.WARNING(f"Profil transit mis a jour: {username} ({', '.join(fields)})"))
                else:
                    self.stdout.write(self.style.SUCCESS(f"Profil transit cree: {username}"))

        self.stdout.write(
            self.style.SUCCESS(
                "Seed termine. Utilisateurs: admin_general, supplier_demo, wholesaler_demo, transit_demo, buyer_demo."
            )
        )
