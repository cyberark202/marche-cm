# Rapport d'écarts — Market_CM_Buisness/docs vs code (2026-07-17)

Périmètre : les 30 documents de `Market_CM_Buisness/docs` (00–29) comparés au
backend Django + 4 apps Flutter. Ce rapport clôt le cycle « écarts → plan →
questions → application » : les 10 lots décidés ont été implémentés et testés.

## 1. Ce qui a été livré (10 lots, backend)

| Lot | Doc(s) | Livré | Preuve |
|---|---|---|---|
| 1. Config plateforme à chaud | 03, 16 | `PlatformSetting` historisé (ancienne valeur, acteur, date) + API admin `/api/admin/platform-settings/` avec validateurs par clé | tests appconfig |
| 2. Règles financières wallet | 05 | Plafonds par niveau KYC (dépôt/retrait/solde), frais de retrait paramétrés, pénalité de dormance planifiée | tests wallets |
| 3. Validation vendeur 24 h | 13, 22 | Compte à rebours d'acceptation vendeur ; expiration auto = annulation + remboursement intégral (tâche Celery) | tests orders |
| 4. Dispatch 15 min + OTP collecte | 07 | Offre de course avec expiration 15 min et ré-offre au suivant ; OTP de collecte vendeur→livreur (hash, TTL 5 min) | tests logistics |
| 5. États produit + modération | 12, 22 | FSM produit DRAFT→PENDING_REVIEW→PUBLISHED/REJECTED/SUSPENDED/ARCHIVED + file de modération admin | tests catalog |
| 6. Types d'annonces | 01, 12 | `listing_type` PHYSICAL/SERVICE/DIGITAL/JOB : champs conditionnels, pas de stock pour service/numérique, livraison uniquement pour physique | tests catalog |
| 7. Rôles admin granulaires | 17 | Sous-rôles admin (SUPPORT, MODERATION, FINANCE, SUPER) via `admin_scope` + permission `HasAdminScope` sur les endpoints sensibles | tests accounts |
| 8. Location (rentals) | 14, 22 | App `rentals` complète : annonces (KYC 2 + preuve de propriété), réservation, séquestre loyer+caution, OTP remise/retour, clôture conforme, litige avec arbitrage caution par l'admin, commission location paramétrée | 5 tests bout-en-bout |
| 9. KYC niveau 3 + expiration | 06 | Niveau `PROFESSIONAL` (RCCM/NIU), `expiry_date` sur les pièces d'identité, tâche quotidienne : alerte à J-30 (une fois) puis rétrogradation `kyc_level=0` à l'échéance | 3 tests compliance |
| 10. Notifications enrichies | 10 | `category` (11 valeurs) + `priority` (4), préférences utilisateur (`/api/notifications/preferences/`), filtre `?category=&unread=1` ; SECURITY/CRITICAL jamais supprimables | 4 tests notifications |

Migrations créées : appconfig, wallets, orders, logistics, catalog, accounts,
rentals (0001), compliance (0002), notifications (0002).

## 1 bis. Alignement frontend (livré le 2026-07-17, même journée)

Les 4 apps Flutter consomment désormais les nouveaux endpoints — analyze 0 issue ×4 :

| App | Écrans livrés |
|---|---|
| Vendeur (`app/`) | « Mes locations » (annonces + preuve de propriété + photo), « Réservations reçues » (accepter/refuser, OTP remise, confirmation restitution, clôture, litige), sélecteur type d'annonce (physique/service/numérique/emploi) au formulaire produit, préférences de notifications |
| Clients | « Louer un bien » (recherche + réservation par plage de dates + paiement séquestre), « Mes locations » (payer, confirmer remise par code, restituer, litige), préférences de notifications |
| Admin | File de modération produits (filtre par statut + suspendre/refuser/rétablir avec motif), arbitrage litiges location (répartition caution), page Configuration réécrite : éditeur temps réel des platform-settings avec step-up 2FA (remplace l'ancienne page en dur, lecture seule) |
| Driver | Préférences de notifications (`/profile/notifications`) |

Ajustements backend faits en passant : filtre `?status=` sur la liste produits
réservé à l'admin (file de modération, +4 tests), endpoint préférences accepte
PATCH.

## 2. Écarts résiduels (non traités, par choix ou hors périmètre)

### Doc 11 — Recherche & recommandation
La recherche reste `icontains` (O(N)) ; pas de full-text PostgreSQL, pas de
moteur de recommandation. Déjà identifié dans docs/PLAN_AMELIORATION_UIUX_BACKEND.md (lot B1).

### Doc 27 — Détection de fraude IA
`apps/fraud` reste à règles fixes (seuils, vélocité). Pas de scoring ML. Le doc
le présente comme une phase ultérieure ; écart assumé.

### Doc 25/26 — DevOps & monitoring
Helm/EKS prêts mais non déployés (mémo projet) ; pas d'APM ni de dashboards
Grafana. Hors périmètre de ce cycle.

### Divers assumés
- Paiement : NotchPay uniquement (pas d'Orange Money direct, doc 05 le liste en option).
- Litiges location : arbitrage admin sur la caution livré ; pas de médiation à
  étapes multiples (doc 08 la décrit pour les commandes, déjà couverte).
- iOS : toujours non buildé (contrainte matérielle connue).

## 3. Verdict

Le backend couvre désormais les règles métier des docs 01–17 et 22 à l'exception
de la recherche avancée (doc 11) et du ML fraude (doc 27), et les 4 apps
exposent ces fonctionnalités (section 1 bis). Écarts restants : recherche FTS,
ML fraude, déploiement EKS, et le raffinement UX des nouveaux écrans (v1
fonctionnelle, pas encore au niveau du design system handoff).

Résultat de la suite complète : voir section tests ci-dessous.

## 4. Tests

- Suite complète backend : **437 tests, 0 échec** (2026-07-17, ~27 min).
- Nouveaux tests de ce cycle : appconfig, wallets, orders, logistics, catalog,
  accounts, rentals (5), compliance (3), notifications (4).
