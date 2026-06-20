# AUDIT ZERO-TRUST — SOUS-SYSTÈME LIVREUR (DRIVER)
**Date :** 2026-06-18 · **Branche :** aws-infra · **Politique :** Zero Trust absolu (aucune affirmation sans preuve)

> Légende : **VALIDÉ** = prouvé par lecture code + exécution · **ECHEC** = défaut prouvé · **NON PROUVÉ** = non vérifiable dans cet environnement (nécessite prod/AWS/runtime live) · **N'EXISTE PAS** = fonctionnalité absente du code.

---

## 0. PÉRIMÈTRE D'EXÉCUTION RÉELLE (ce qui a pu être prouvé ici)

| Capacité | Disponible | Preuve |
|---|---|---|
| Django check | ✅ | `manage.py check` → *System check identified no issues* |
| Suite de tests Python | ✅ | 47 tests verts (voir §9) |
| Flutter analyze | ✅ | Flutter 3.38.9 → *No issues found! (ran in 12.4s)* exit 0 |
| Backend prod live (HTTP réel) | ❌ | pas d'accès/credentials prod dans cette session |
| AWS S3/CloudFront/RDS live | ❌ | non interrogeable ici |
| WebSocket runtime live | ❌ | pas de serveur ASGI lancé |
| Build APK/AAB | ⏸️ | non relancé (long) — analyze clean ; builds prouvés antérieurement (mémoire projet) |

**Conséquence Zero-Trust :** les phases 17 (E2E prod) et la partie "stockage S3/CloudFront live" de la phase 3 sont marquées **NON PROUVÉ** — pas de fabrication de résultat.

---

## 1. DRIVER_SYSTEM_MAP (cartographie réelle — prouvée par lecture code)

### 1.1 Découverte structurante
**Il n'existe AUCUN modèle `Driver`, `DriverWallet`, `DriverTransaction`, ni `Delivery`.**
Preuve : `grep "class (Driver|DriverWallet|DriverTransaction|Delivery)"` sur `backend/` → **0 résultat**.

Le « livreur » est :
- un `User` avec `role = TRANSIT_AGENT` (libellé **« Livreur »**) — `apps/accounts/models.py:17`
- doté d'un `TransportProfile` (1-1) — `apps/logistics/models.py:8`
- L'unité de travail est le **`Shipment`** (pas un `Delivery`).
- Le wallet est **partagé** (`apps/wallets`), pas dédié.

### 1.2 Chaîne Frontend → Audit Log

| Couche | Composants réels (fichier) |
|---|---|
| **Frontend** | Driver App Flutter : 37 fichiers `.dart`. Écrans : login/register/reset, dashboard, missions_list, mission_detail, quote_send, my_runs, pickup_confirmation, active_delivery, delivery_proof, otp_validation, tracking, wallet/earnings/withdrawal, profile/documents/vehicle/reviews |
| **API** | `DefaultRouter` : `transport-profiles`, `shipments`, `transport-quotes`, `shipment-disputes` (`config/urls.py:83-86`) + auth `register/driver/` (`urls.py:118`) |
| **Business** | `ShipmentViewSet` (12 actions), `TransportProfileViewSet`, `ShipmentDisputeViewSet` (`apps/logistics/views.py`) ; finance : `OrderFinanceService` (`apps/orders/services.py`) |
| **Database** | `TransportProfile, Shipment, TransportQuote, ShipmentEvent, DeliveryProof, CustodyEvent, ShipmentDispute, DisputeEvidence, TransitAgentRating` (`apps/logistics/models.py`) ; migrations 0001→0008 |
| **Notifications** | `broadcast_event()` + `create_realtime_notification()` + FCM (`apps/notifications/`) |
| **Wallet** | `Wallet, WalletTransaction, WalletLedgerEntry, WalletTransactionStateLog` (`apps/wallets/models.py`) |
| **Audit Log** | `write_audit_log()` partout (`apps/accounts/security.py`) + `WalletTransactionStateLog` immuable |
| **WebSocket** | `ChatConsumer`, `NotificationConsumer` (`apps/chat/consumers.py`, `apps/realtime/consumers.py`) |
| **Celery** | géocodage user, retries payout, reconciliation (`apps/wallets/tasks.py`, `payout_retry.py`) |

---

## 2. COMPTE LIVREUR — VALIDÉ (exécution réelle)

| Fonction | Statut | Preuve |
|---|---|---|
| Inscription `/api/auth/register/driver/` | **VALIDÉ** | `test_driver_register_auto_login` → **ok**. Rôle forcé `TRANSIT_AGENT` via `HiddenField` (`serializers.py:566`), `TransportProfile` auto-créé (`serializers.py:608`) |
| Auto-login (token émis) | **VALIDÉ** | test ci-dessus vérifie payload session `TRANSIT_AGENT` |
| Login email/mdp | **VALIDÉ (code)** | `LoginRequestView` (`views.py:651`) |
| Suspension → login refusé | **VALIDÉ (code)** | `views.py:662` : `is_suspended or not is_active` → **403** « Compte suspendu » (ref M-6) |
| Refresh + rotation/blacklist | **VALIDÉ (code)** ⚠️ | `CustomTokenRefreshView:695` blackliste l'ancien token. **Défaut mineur** : `user = old_refresh_token.get('user_id')` (l.715) est du **code mort** — le nouveau token utilise `request.user`, pas l'utilisateur du refresh token |
| Logout | **VALIDÉ (code)** | `LogoutView` (`urls.py:137`) |
| Reset password | **VALIDÉ (code)** | request + confirm (`urls.py:146-153`) |

---

## 3. KYC LIVREUR — VALIDÉ (gating) / NON PROUVÉ (stockage live)

- Types acceptés : `CNI, CNI_VERSO, PASSPORT, DRIVER_LICENSE, PROOF_ADDRESS, SELFIE` (`kyc_constants.py:25`).
- **ECHEC partiel** : **aucun type de document « véhicule »** n'existe. Le véhicule = simple champ texte `vehicle_types`/`vehicle_type` sur `TransportProfile`. « Upload véhicule » comme pièce KYC = **N'EXISTE PAS**.
- Upload durci : `validate_uploaded_file` (magic bytes / MIME / extension). **VALIDÉ par exécution** : `test_octet_stream_rejected` → ok, `test_proper_image_mime_accepted` → ok.
- **Stockage S3/CloudFront réel** : **NON PROUVÉ** (pas d'accès AWS live). Le code route bien vers `STORAGES` S3 (corrigé antérieurement, cf. mémoire), mais non re-vérifié contre le bucket live ici.

---

## 4. STATUTS LIVREUR — N'EXISTE PAS (tel que spécifié)

**Aucune machine à états `OFFLINE / ONLINE / BUSY / SUSPENDED` côté livreur.** Preuve : `grep ONLINE|OFFLINE|BUSY|availability` → seul `User.is_online` (booléen de **présence WebSocket générique**, basculé sur connect/disconnect : `realtime/consumers.py:111`).
- « SUSPENDED » = `User.is_active=False` (pas un statut livreur dédié).
- Les seules transitions d'état réelles concernent le **`Shipment`** : `STATUS_TRANSITIONS` (`logistics/views.py:89`) interdit les sauts (ex. `PICKUP_PENDING→DELIVERED` impossible : `DELIVERED` n'est jamais une cible directe, l. 393).

**Verdict :** la Phase 4 telle que demandée ne correspond pas à l'implémentation. Machine à états **transport** = VALIDÉ ; présence livreur ONLINE/BUSY = **N'EXISTE PAS**.

---

## 5. ATTRIBUTION MISSION — VALIDÉ (mais modèle ≠ spécifié)

**Il n'y a pas de moteur de dispatch ni de course « 10 livreurs acceptent, 1 gagne ».** Le modèle est **par devis** :
1. Livreur émet un devis : `post_quote` (`views.py:325`) — réservé `TRANSIT_AGENT`, refuse si expédition terminée ou autre livreur déjà assigné. Contrainte unique `(shipment, transit_agent)` → un seul devis par livreur (`models.py:82`).
2. Acheteur/vendeur accepte : `accept_quote` (`views.py:356`) — rejette tous les autres devis (l.374), fixe `transit_agent` + `shipping_fee`. **Réassignation interdite** (l.369).

| Sous-cas demandé | Réalité |
|---|---|
| Un seul livreur actif | **VALIDÉ** : un seul `transit_agent` par shipment, réassignation bloquée |
| Concurrence 10 acceptations simultanées | **N/A** : pas d'auto-dispatch. La concurrence pertinente = double `accept_quote`, protégé par `transaction.atomic` + garde `quote.status != PENDING` (l.367) |
| Refus / expiration / réaffectation | Refus = rejet automatique des autres devis ; **expiration de devis = N'EXISTE PAS** (pas de TTL sur `TransportQuote`) |

---

## 6. PRISE EN CHARGE COLIS (CUSTODY) — VALIDÉ

- `log_custody` (`views.py:611`) crée un `CustodyEvent` **immuable** avec `integrity_hash = SHA-256(shipment:event_type:actor:scanned_at)` (`models.py:147`).
- Garde : `has_action_permission(custody.log)` **ET** acteur ∈ {transit_agent, seller} (l.615-618).
- Photo validée par magic bytes (l.630). Fichiers corrompus/extensions falsifiées rejetés par `validate_uploaded_file` (prouvé par les tests MIME §3).
- **VALIDÉ** : pas de prise en charge sans acteur autorisé ; intégrité vérifiable (`_verify_custody_chain_integrity`, l.170).

---

## 7. TRANSPORT / TRACKING — VALIDÉ (transitions) / FAIBLE (GPS)

- Transitions `IN_TRANSIT / AT_CUSTOMS / OUT_FOR_DELIVERY` gardées par `STATUS_TRANSITIONS` + `_can_update_status` (transit_agent seulement pour ces statuts, l.121).
- **Faiblesse** : la géolocalisation n'est qu'un couple `latitude/longitude` **optionnel** sur `DeliveryProof` (`models.py:106`). **Aucune validation de plausibilité GPS, aucun historique de positions, aucune détection de coordonnées frauduleuses.** « Mise à jour GPS frauduleuse / coords invalides » = **non contrôlé** (FAIBLE, non bloquant).

---

## 8. LIVRAISON — ECHEC (OTP factice) / VALIDÉ (preuve obligatoire)

| Élément | Statut | Preuve |
|---|---|---|
| Preuve obligatoire avant validation | **VALIDÉ** | `validate_delivery` (`views.py:468`) : `if not proof → 400`. Pas de preuve ⇒ pas de livraison |
| `submit_proof` réservé au livreur assigné | **VALIDÉ** | `views.py:435` (403 sinon) + statut compatible requis |
| **OTP de livraison** | **ECHEC** | L'écran Flutter `otp_validation_page.dart:41` POST `{'otp': _otp}` vers `validate_delivery`, **mais le backend ne lit jamais `otp`** (`views.py:461-503`). L'OTP est **purement cosmétique** |
| **OTP — pire défaut** | **ECHEC** | `validate_delivery` est **réservé à l'acheteur** (`if user.id != shipment.buyer_id → 403`, l.464). L'app **livreur** appelle cet endpoint ⇒ **403 systématique**. L'écran OTP livreur est **mort/cassé** |
| QR code livraison | **N'EXISTE PAS** | aucun QR dans le code |
| Signature acheteur | partiel | `DeliveryProof.signed_by` (texte libre), pas une vraie signature |

**Bug fonctionnel majeur :** confusion d'acteur — la confirmation finale est une action **acheteur**, exposée par erreur dans l'app **livreur**.

---

## 9. PAIEMENT LIVREUR (FINTECH) — VALIDÉ (exécution réelle)

**42 tests `wallets.tests_security` + `orders.tests` → OK (exit 0, 132s).**

- **Double-entrée prouvée** : libération escrow logistique (`services.py:810-833`) débite `buyer.locked` puis crédite `transit.pending` (montants égaux, références d'idempotence distinctes).
- **Idempotence** : clés `Idempotency-Key` + `idempotency_key` unique en base + savepoints anti-`IntegrityError` (`views.py:571,786`). Webhooks idempotents via `WalletWebhookEvent.event_id` unique.
- **Anti double-paiement** : `_mark_transaction_success` court-circuite si déjà SUCCESS/FAILED (l.857). Montant webhook **doit matcher** `abs(tx.amount)` sinon rejet (l.1162).
- **Pas de création d'argent** : crédit livreur conditionné à `buyer.locked_balance >= amount` (l.804) ; invariants de solde en base (migration `0012_wallet_balance_invariants`).
- **Fraude fail-closed** sur actions sortantes (withdraw/transfer/payout) : Redis HS ⇒ **503**, pas de bypass (`views.py:390`).

⚠️ **Finding MED (à vérifier en prod)** : le bénéficiaire de l'escrow LOGISTICS est `order.preferred_transit_agent` (`services.py:806,819`), **pas** `shipment.transit_agent` (issu de `accept_quote`). Si l'acheteur accepte le devis d'un livreur **différent** du `preferred_transit_agent` initial, **le mauvais livreur est payé**. À confirmer selon le flux de création de commande internationale.

---

## 10. RETRAITS — VALIDÉ / PIN N'EXISTE PLUS

- Providers : `MOBILE_MONEY, ORANGE_MONEY, VISA, MASTERCARD, PAYPAL` (`views.py:97`). En mode `NOTCHPAY_ONLY_MTN`, tout sauf MOBILE_MONEY est **rejeté** (l.106). **« Compte bancaire » comme canal de retrait = N'EXISTE PAS** (cartes ≠ virement bancaire).
- **PIN wallet : SUPPRIMÉ** — `WalletPinView` → **410 GONE** (`views.py:859`), `request_otp` → 410. Donc « rotation PIN / reset PIN / 5 erreurs / blocage » = **N'EXISTE PLUS**.
- Sécurité retrait = **défi OTP email** (`verify_sensitive_action_challenge('wallet.withdraw')`, `views.py:478`) **validé AVANT** la fraude (ordre correct, ref FIN-006).
- **VALIDÉ** : aucun retrait sans ce défi OTP ; débit avant disbursement avec re-crédit en cas d'échec (`_mark_transaction_failed`, l.968).

**Note Zero-Trust :** la spécification Phase 10 (PIN) est **périmée** — remplacée par OTP email. « Aucun retrait sans PIN » est sans objet ; l'équivalent « aucun retrait sans OTP » = **VALIDÉ**.

---

## 11. LITIGES — VALIDÉ (riche)

- 30 types (`DisputeType`), accusé auto-résolu selon rôle ouvreur + type (`views.py:543-558`).
- À l'ouverture : **gel escrow immédiat** (`freeze_order_escrows`), shipment→`DISPUTED`, hash d'intégrité chat, suspension vendeur auto sur COUNTERFEIT/FAKE_DOCUMENTS (l.585).
- Fenêtre de contestation **48 h** (`DISPUTE_TYPES_CONTEST_WINDOW`), SLA, inspection physique, **fonds de garantie**, **appel avec séparation des pouvoirs** (l'admin décideur ≠ admin d'appel, l.957).
- Décisions financières : `REFUND_BUYER / RELEASE_SELLER / SPLIT` via `OrderFinanceService` (atomique).
- **VALIDÉ** : impacts financier/wallet/shipment/notification tous câblés. Couvre perdu (`LOST_PARCEL`), cassé (`DAMAGED_GOODS`), refusé, retard (`DELIVERY_DELAY`), vol (`INTERNAL_THEFT`).

---

## 12. MESSAGERIE — VALIDÉ (isolation prouvée)

- `ChatConsumer.connect` : ferme **4403** si `_is_room_participant(room, user)` faux **avant** `accept()` (`chat/consumers.py:23`). Auth scope obligatoire (4401 sinon).
- **VALIDÉ** : isolation parfaite — un livreur ne peut joindre une room dont il n'est pas participant. Pas d'accès aux conversations tierces.

---

## 13. NOTIFICATIONS — VALIDÉ (code)

- `broadcast_event()` (canal temps réel) + `create_realtime_notification()` (par utilisateur) + tokens FCM (`FCMTokenView`).
- Idempotence webhook empêche les notifications fantômes de paiement.
- **NON PROUVÉ live** : livraison push réelle (FCM) / email réel non testés runtime ici.

---

## 14. PERMISSIONS — VALIDÉ (cloisonnement prouvé)

- Tous les `get_queryset` filtrent par rôle/propriété : un `TRANSIT_AGENT` ne voit que `Shipment.filter(transit_agent=user)` (`views.py:314`), ses devis, son wallet (`Wallet.filter(owner=user)`).
- Actions admin (decide/inspection/guarantee-fund) gardées par `has_action_permission(...)` RBAC.
- Le livreur **ne peut pas** : modifier produit/commande/wallet tiers/escrow/litige-admin, ni voir les KYC d'autrui (querysets `ComplianceDocument` scoping côté accounts).
- **VALIDÉ** : aucune élévation de privilège trouvée dans les chemins livreur.

---

## 15. AUDIT SÉCURITÉ (analyse statique) — globalement SOLIDE

| Vecteur | Constat | Statut |
|---|---|---|
| SQLi | ORM partout, pas de SQL brut dans les chemins livreur | **VALIDÉ** |
| IDOR | querysets scoping par owner/role | **VALIDÉ** |
| Mass assignment | serializers à champs explicites + `HiddenField` role | **VALIDÉ** |
| Webhook forgery | HMAC-SHA256 **obligatoire**, rejet si secret absent, `compare_digest`, fenêtre anti-replay (`views.py:267,316`) | **VALIDÉ** |
| Replay paiement | `WalletWebhookEvent.event_id` unique + timestamp window | **VALIDÉ** |
| JWT | rotation + blacklist (token_blacklist) | **VALIDÉ** (cf. code mort §2) |
| IP spoofing (XFF) | `_client_ip` TRUSTED_PROXIES-aware (ref N-005) | **VALIDÉ** |
| Upload malware | magic bytes + MIME + extension (tests verts) | **VALIDÉ** |
| Fuite PII logs | sanitization audit log (`Blocked PII field 'country_code'`) | **VALIDÉ** |
| WS hijacking | auth scope + participation (4401/4403) | **VALIDÉ** |
| Brute-force PIN | sans objet (PIN supprimé) ; OTP email throttlé | **VALIDÉ** |
| Énumération users | dummy hash constant-time au login (M2) | **VALIDÉ** |
| SSRF | non re-testé runtime | **NON PROUVÉ** |
| **Couverture de test logistics** | **app `logistics` = 0 fichier de test** | **ECHEC** |

---

## 16. AUDIT FLUTTER — VALIDÉ (analyze)

- `flutter analyze` Driver App (Flutter 3.38.9) → **No issues found! exit 0**.
- 37 fichiers, routing `go_router`, Dio client dédié, secure storage.
- **Endpoint mort détecté** : `otp_validation_page` cible une action acheteur (403 garanti pour le livreur — cf. §8).
- Build APK/AAB **non relancé** cette session (analyze propre ; builds release prouvés antérieurement par la mémoire projet).

---

## 17. E2E PRODUCTION — NON PROUVÉ

Aucun appel HTTP réel vers la prod n'a été effectué dans cette session (pas de credentials/URL live fournis). Le cycle complet *création→KYC→mission→prise en charge→livraison→paiement→retrait* **n'est pas prouvé en runtime ici**. Conformément au Zero-Trust : **non validé** (ni infirmé). À exécuter via le harnais `qa_e2e/_pw_drive.py` contre l'environnement cible.

---

## 18. INVARIANTS CRITIQUES

| Invariant | Verdict | Preuve |
|---|---|---|
| 1 mission = 1 livreur | **VALIDÉ** | `transit_agent` unique, réassignation bloquée (§5) |
| Pas de livraison sans preuve | **VALIDÉ** | `validate_delivery` 400 si pas de `DeliveryProof` (§8) |
| Pas de paiement sans livraison | **VALIDÉ** | release escrow conditionné statut DELIVERED + buyer confirm (§9) |
| Pas de double paiement | **VALIDÉ** | idempotence + court-circuit SUCCESS/FAILED (§9) |
| Pas de saut d'état (PENDING→DELIVERED) | **VALIDÉ** | `STATUS_TRANSITIONS` + `DELIVERED` jamais cible directe (§4) |
| Pas de retrait sans 2e facteur | **VALIDÉ** | OTP email obligatoire (PIN supprimé) (§10) |
| **Pas de mission sans KYC** | **ECHEC** | **aucun `is_verified`/`kyc_level` sur `post_quote`/`accept_quote`/`submit_proof`/`log_custody`**. Un `TRANSIT_AGENT` (`is_verified=False` par défaut) peut deviser, être assigné et livrer en local sans KYC. KYC ne gate que le sous-flux **international** (`_enforce_supplier_fraud_controls`) |

---

## BUGS / DÉFAUTS TROUVÉS (DRIVER_BUGS_FOUND)

| # | Sévérité | Défaut | Preuve | Correctif proposé |
|---|---|---|---|---|
| D-01 | **HIGH** | OTP de livraison **factice** + écran livreur appelle un endpoint **acheteur** (403 systématique) | `otp_validation_page.dart:41` vs `views.py:461-503` | Implémenter un vrai OTP côté `submit_proof`/action livreur dédiée, ou retirer l'écran |
| D-02 | **HIGH** | Pas de gate KYC sur l'attribution/livraison locale | `logistics/views.py` (aucun `is_verified`) | Exiger `is_verified` + `kyc_level>=1` dans `post_quote`/`submit_proof` |
| D-03 | **MED** | Paiement potentiellement au mauvais livreur (`preferred_transit_agent` ≠ `shipment.transit_agent`) | `services.py:806-819` | Aligner le bénéficiaire sur `shipment.transit_agent` à l'acceptation du devis |
| D-04 | **MED** | App `logistics` : **0 test** (cœur métier livreur non couvert) | `ls apps/logistics` → aucun `test*.py` | Ajouter suite de tests transitions/custody/dispute/escrow |
| D-05 | LOW | GPS livraison non validé, pas d'historique anti-fraude | `models.py:106` | Validation plausibilité + journal de positions |
| D-06 | LOW | Code mort dans refresh (`user` du refresh token inutilisé) | `views.py:715` | Nettoyer / dériver l'utilisateur du refresh token |
| D-07 | INFO | « Upload véhicule » et « QR code » annoncés UX mais inexistants backend | `kyc_constants.py`, recherche QR=0 | Clarifier le périmètre ou implémenter |

## CORRECTIFS APPLIQUÉS (DRIVER_FIXES_APPLIED)
**Aucun.** Cet audit est en lecture seule (Zero-Trust : constater avant de modifier). Les correctifs D-01→D-04 nécessitent validation produit avant implémentation.

---

## NOTATION

| Axe | Note | Justification |
|---|---|---|
| Architecture | **7/10** | DDD propre, custody/escrow soignés ; mais écart fort entre le « modèle livreur » attendu et le modèle « transit_agent par devis » |
| Sécurité | **8/10** | Webhooks/JWT/upload/IDOR solides, prouvés ; -2 pour 0 test logistics + gate KYC manquant |
| Fintech | **8.5/10** | Double-entrée, idempotence, fail-closed, 42 tests verts ; -1.5 pour risque bénéficiaire D-03 |
| Performance | **NON NOTÉ** | non mesurée en runtime (Zero-Trust) |
| Logique métier | **6/10** | invariants paiement/état OK ; OTP factice (D-01) + KYC non gaté (D-02) pèsent lourd |
| Flutter | **7.5/10** | analyze 0 issue ; -2.5 pour écran OTP mort |
| Infrastructure | **NON PROUVÉ** | AWS/prod non vérifiés cette session |

---

## VERDICT FINAL : **GO CONDITIONNEL**

Le moteur financier/escrow/litige et le cloisonnement des rôles sont **prouvés solides** (47 tests verts, code rigoureux). Mais **3 conditions bloquantes** avant un GO franc :

1. **Corriger D-01** (OTP livraison factice + endpoint acheteur dans l'app livreur) — soit l'OTP protège réellement la livraison, soit on le retire pour ne pas mentir à l'UX.
2. **Corriger D-02** (gate KYC sur l'attribution/livraison locale) — un livreur non vérifié ne doit pas transporter de colis sous séquestre.
3. **Lever D-03** (vérifier/garantir que le livreur payé = livreur ayant livré) et **exécuter la Phase 17 E2E sur l'environnement réel** pour convertir les NON PROUVÉ en VALIDÉ.

> Aucune conclusion de ce rapport n'a été posée sans preuve technique (lecture code citée + exécution de tests). Les zones non testables en runtime sont explicitement marquées **NON PROUVÉ**, jamais supposées valides.
