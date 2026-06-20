# CORRECTIFS DRIVER — D-01 / D-02 / D-03 (+ bug latent)
**Date :** 2026-06-20 · **Branche :** aws-infra
**Preuve d'exécution :** 62 tests Django OK (dont 4 nouveaux tests logistics) · `flutter analyze` Driver App = 0 issue · `manage.py check` = 0 · `makemigrations --check` = aucune dérive.

Suite à l'audit Zero-Trust du sous-système livreur (verdict GO CONDITIONNEL), les 3 blocages ont été corrigés.

## D-01 — OTP de livraison réel (était factice + endpoint cassé)
**Avant :** la page Flutter envoyait l'OTP à `validate_delivery` (réservé à l'acheteur → 403 systématique pour le livreur) ; le backend ignorait totalement le champ `otp`.
**Après :**
- Modèle `Shipment` : `delivery_otp_hash` + `delivery_otp_expires_at` (migration `0009_shipment_delivery_otp`). Seul le **hash salé** (`make_password`) est stocké, jamais le code.
- `ShipmentViewSet.issue_delivery_otp` (livreur assigné) : génère un code 4 chiffres (`secrets.randbelow`), TTL 30 min, l'envoie à l'**acheteur** par notification.
- `ShipmentViewSet.confirm_delivery` (livreur assigné) : vérifie le code (`check_password`), exige une preuve photo, expiration et **usage unique** ; transitionne `DELIVERED` + libère l'escrow avec `actor=buyer` (la possession du code prouve le consentement acheteur, l'invariant « release acheteur » est préservé).
- Flutter `otp_validation_page.dart` : appelle `confirm_delivery`, déclenche `issue_delivery_otp` à l'ouverture, bouton « Renvoyer le code ».

Fichiers : `apps/logistics/views.py`, `apps/logistics/models.py`, `apps/logistics/migrations/0009_shipment_delivery_otp.py`, `frontend/Driver App/app/lib/features/delivery/presentation/otp_validation_page.dart`.

## D-02 — Gate KYC livreur (était absent en local)
Helper `_require_driver_kyc(user)` : exige `is_verified` **et** `kyc_level ≥ 1` (admin exempté). Appliqué à `post_quote`, `submit_proof`, `log_custody` (livreur uniquement, pas le vendeur), `issue_delivery_otp`, `confirm_delivery`. Un livreur non vérifié reçoit désormais **403** au lieu de pouvoir prendre une mission.

Fichier : `apps/logistics/views.py`.

## D-03 — Paiement au bon livreur (était `preferred_transit_agent`)
`release_logistics_escrow_after_buyer_confirmation` paie désormais `shipment.transit_agent` (le transporteur réellement assigné via l'acceptation du devis), avec repli sur `preferred_transit_agent` si non assigné. Wallet + `counterparty` alignés sur ce bénéficiaire.

Fichier : `apps/orders/services.py`.

## Bug latent surfacé par les tests (corrigé)
`ShipmentViewSet.get_queryset` filtrait `transit_agent=user` pour un livreur → `get_object()` renvoyait **404** sur toute expédition non assignée, rendant `post_quote` **inatteignable**. Désormais le livreur voit aussi les expéditions **ouvertes** (non assignées, non terminales) pour les deviser.

Fichier : `apps/logistics/views.py`.

## D-04 — Tests logistics (l'app était à 0 test)
Nouveau `apps/logistics/tests.py` — 4 tests, tous verts :
- `test_unverified_driver_cannot_quote` (D-02 : 403 non-KYC, 201 KYC)
- `test_delivery_otp_is_real_and_driver_can_confirm` (D-01 : hash stocké, mauvais code → 400, sans preuve → 400, bon code + preuve → DELIVERED + payout, code brûlé)
- `test_driver_confirm_is_not_a_buyer_only_403` (D-01 : plus de 403 piège)
- `test_release_pays_actual_carrier_not_stale_preferred` (D-03 : le transporteur est payé, pas le decoy)

## Reste à faire (non bloquant code)
- **D-05** : validation de plausibilité GPS + historique positions.
- **D-06** : nettoyer le code mort dans `CustomTokenRefreshView`.
- **Phase 17** : E2E sur environnement prod réel (non exécutable hors accès live).
