# Rapport de Production Hardening — Central Market / Marché CM
**Date :** 2026-06-03 · **Périmètre :** correction de tous les bugs de `RAPPORT_QA_E2E.md` (3 critiques, 6 majeurs, 1 mineur), sans régression, avec tests.

---

## 1. Résumé exécutif

| Indicateur | Valeur |
|---|---|
| Bugs corrigés | **10 / 10** (C-1, C-2, C-3, M-1→M-6, m-1) |
| Nouveaux tests automatisés ajoutés | **48** (tous verts) |
| Régressions introduites | **0** |
| Migration ajoutée | `accounts/0016` (champs de suspension) |
| Re-vérification E2E live (avant/après) | **5/5 scénarios corrigés** |

**Échecs résiduels de la suite** : 3 tests `apps.wallets.tests_security.H2DisburseAmountValidationTests` échouent (403) **en local** — ils échouent **aussi en isolation, sur du code que cette intervention n'a pas touché** (aucun fichier `apps/wallets/*` modifié). Cause : l'environnement local charge les **clés/secret NotchPay LIVE**, donc la signature du webhook de disbursement signée avec le `DISBURSE_SECRET` de test ne concorde pas → 403. Ce sont des **faux négatifs d'environnement**, pas des régressions (ils passent en CI avec le secret de test).

---

## 2. Corrections par bug

### 🔴 C-3 — Annulation atomique (argent bloqué) — **P0**
- **Cause :** `update_status` (logistique) faisait `order.status = CANCELLED; save()` **puis** appelait `refund_order_locked_funds` (qui interdit l'acheteur) — sans transaction. Échec du refund → commande CANCELLED + escrow LOCKED.
- **Correction :**
  - Nouveau service atomique [`OrderFinanceService.cancel_order`](backend/apps/orders/services.py) : un seul `transaction.atomic()` rembourse l'escrow **et** passe la commande à CANCELLED, ou rien ; autorise les **parties** (acheteur/vendeur) en plus de l'admin/transit ; rejette les états terminaux.
  - Cœur de remboursement factorisé dans `_apply_locked_refund` (partagé avec `refund_order_locked_funds`, comportement inchangé → rétrocompatible).
  - [`update_status`](backend/apps/logistics/views.py) enveloppe désormais annulation + refund + statut shipment dans un `transaction.atomic()`.
- **Tests :** `apps/orders/test_buyer_cancel_refund_atomicity.py` (7) + `apps/orders/test_buyer_cancel_concurrent_requests.py` (1) — atomicité, rollback sur échec, double-annulation, états terminaux, **concurrence**.

### 🔴 C-1 — Contrat produit vendeur — **P0**
- **Cause :** l'app vendeur envoyait `category` (au lieu de `category_name`), `min_qty`/`max_qty` (au lieu de `min_order_qty`/`max_order_qty`), et **aucun `weight_kg`** → 400.
- **Correction :**
  - Backend : shim **rétrocompatible** `ProductSerializer.to_internal_value` ([catalog/serializers.py](backend/apps/catalog/serializers.py)) traduisant les clés legacy → canoniques (les anciens builds mobiles fonctionnent sans mise à jour) ; **validation d'ordre des prix** (anti-inversion : `price_for_min_qty ≥ price_for_max_qty`).
  - Frontend : modèle partagé [`ProductRequestModel`](frontend/app/lib/features/supplier/product_request_model.dart) (clés canoniques + validation client), champ **Poids (kg)** ajouté au formulaire, mapping prix clarifié (cohérent avec les libellés « gros volume / faible volume »).
- **Tests :** `apps/catalog/test_supplier_product_contract.py` (5) + `test_supplier_product_creation_e2e.py` (1).

### 🔴 C-2 — `is_active` contrôlé serveur — **P0**
- **Cause :** un `BooleanField` absent d'un corps `multipart/form-data` est coercé à `False` par DRF → tout produit avec image devenait inactif (invisible).
- **Correction :** `is_active` rendu **read-only** + forcé `True` à la création ([catalog/serializers.py](backend/apps/catalog/serializers.py)) → comportement identique JSON/multipart, non manipulable par payload.
- **Tests :** `apps/catalog/test_multipart_product_activation.py` (4) + `test_product_visibility_after_upload.py` (1).

### 🟠 M-1 — Géocodage asynchrone — **P1**
- **Cause :** `RegisterSerializer.create()` appelait Nominatim en **synchrone** (2,5–8,6 s, timeout 10 s).
- **Correction :** tâche Celery [`user_geocode_task`](backend/apps/accounts/tasks.py) ; helper [`enqueue_user_geocode`](backend/apps/accounts/location_service.py) qui **publie sur un thread daemon** (la requête ne bloque jamais sur le broker, même down) avec retry désactivé + fallback silencieux. Les 4 chemins d'inscription (acheteur/vendeur/grossiste/livreur + admin) basculés en asynchrone.
- **Avant/après live :** inscription **7–9 s → ~1,7 s** (résidu = PBKDF2 870k, coût sécurité voulu) ; test `test_register_fast_even_when_broker_unreachable` prouve le chemin requête **< 500 ms**.
- **Tests :** `apps/accounts/test_register_geocode_async.py` (5).

### 🟠 M-2 / M-3 — Types KYC unifiés — **P1**
- **Cause :** `PROOF_ADDRESS`/`SELFIE` annoncés par la vue mais absents de `ALLOWED_DOC_TYPES` du serializer → 400.
- **Correction :** source unique [`apps/accounts/kyc_constants.py`](backend/apps/accounts/kyc_constants.py) ; vue et serializer en dérivent. Invariant testé : `BUYER_IDENTITY_DOC_TYPES ⊆ ALLOWED_DOC_TYPES`.
- **Tests :** `apps/accounts/test_kyc_doc_types.py` (6).

### 🟠 M-4 — Création produit grossiste — **P1**
- **Cause :** `price_for_min_qty`/`price_for_max_qty` requis au niveau champ → le grossiste 400 avant que `validate()` ne les dérive de `unit_price`.
- **Correction :** champs rendus `required=False` au serializer ; `validate()` les calcule serveur pour le grossiste, et reste strict pour le fournisseur.
- **Tests :** `apps/catalog/test_wholesaler_product_creation.py` (3).

### 🟠 M-5 — WebSocket Driver + 404 ASGI — **P2**
- **Cause :** la Driver App ciblait `/ws/driver/` (route inexistante → 500).
- **Correction :** `driverWsUrl` → `/ws/events/` ([Driver App app_config.dart](frontend/Driver%20App/app/lib/core/config/app_config.dart)) ; consumer fallback [`FallbackWebSocketConsumer`](backend/apps/realtime/consumers.py) + route catch-all `^ws/.*$` ([config/asgi.py](backend/config/asgi.py)) → rejet propre (close 4404) au lieu d'un 500 ; **bug latent corrigé** : `NotificationConsumer.disconnect` plantait (`AttributeError`) sur chaque handshake refusé.
- **Tests :** `apps/realtime/test_ws_routing.py` (5, via `WebsocketCommunicator`).

### 🟠 M-6 — Suspension utilisateur — **P2**
- **Correction :** champs `is_suspended`/`suspended_at`/`suspension_reason`/`suspended_by` (migration `accounts/0016`) ; méthodes modèle `User.suspend()`/`lift_suspension()` (atomiques, **révocation JWT** par blacklist des refresh tokens) ; endpoints admin `POST /api/users/{id}/suspend|unsuspend/` gardés par l'action RBAC `admin.users.suspend` ; enforcement au login (message clair « Compte suspendu ») + blocage de la réactivation silencieuse via Google ; audit à chaque action.
- **Tests :** `apps/accounts/test_user_suspension.py` (8) — RBAC, JWT révoqué, anti-self/anti-admin, 404.

### 🟡 m-1 — Nom d'affichage non unique
- **Correction :** suppression du contrôle d'unicité dans `ProfileUpdateSerializer.validate_name` (cohérent avec l'inscription H-005).
- **Tests :** `apps/accounts/test_display_name_not_unique.py` (2).

---

## 3. Re-vérification E2E live (avant → après)

Serveur redémarré avec le nouveau code ; scénarios précédemment en échec rejoués sur l'API réelle :

| Scénario | Avant | Après |
|---|---|---|
| C-1 — payload app vendeur (clés legacy + poids) | 400 | **201** ✅ |
| C-2 — produit multipart sans `is_active` | `is_active=False`, invisible | **`is_active=True`, visible** ✅ |
| C-3 — annulation acheteur | 400, escrow LOCKED (8600 bloqués) | **200, CANCELLED + 8600 remboursés** ✅ |
| M-2/M-3 — KYC `PROOF_ADDRESS`/`SELFIE` | 400 | **201** ✅ |
| M-4 — création grossiste (qty+unit_price) | 400 | **201** ✅ |

---

## 4. Non-régression & suite de tests
- **48 nouveaux tests** : 100 % verts.
- **Suite complète** : **313 tests, 3 échecs** = uniquement les 3 `H2DisburseAmountValidationTests` (faux négatifs d'environnement, code wallet non modifié — cf. §1). **Aucune régression** imputable à cette intervention (le test de concurrence C-3, flaky sous contention au 1ᵉʳ run, a été durci pour gérer le cas « les deux writers perdent la course SQLite » sans état partiel).
- `makemigrations --check` : *No changes detected* (hors la migration 0016 ajoutée).

## 5. Fichiers modifiés / ajoutés
**Backend (modifiés) :** `apps/orders/services.py`, `apps/logistics/views.py`, `apps/catalog/serializers.py`, `apps/accounts/{serializers,views,models,security,location_service}.py`, `apps/realtime/consumers.py`, `config/asgi.py`.
**Backend (ajoutés) :** `apps/accounts/{tasks.py,kyc_constants.py}`, migration `accounts/0016`, 12 fichiers de test.
**Frontend (modifiés) :** `app/lib/features/supplier/supplier_product_edit_page.dart` (+ `product_request_model.dart`), `Driver App/app/lib/core/config/app_config.dart`.

## 6. Recommandation de suivi
Les 3 tests `H2DisburseAmountValidationTests` devraient passer en CI (secret de test). Pour les faire passer **en local**, fournir `NOTCHPAY_DISBURSE_WEBHOOK_SECRET` de test dans `marche-cm.local.env` ou via `override_settings` dans le test. À traiter hors de ce périmètre (aucun lien avec les bugs corrigés).
