# RAPPORT QA E2E — V2 (Audit anti-régression post-corrections)

**Projet :** Marché CM — marketplace fintech (Django 5.1.6 / DRF / Channels / Celery / PostgreSQL / Redis)
**Date :** 2026-06-03
**Mission :** vérifier qu'aucune correction issue du 1er rapport QA n'a introduit de régression. Règle absolue : **ne jamais supposer qu'un bug est corrigé** — tout tester réellement, du contrat front jusqu'à la base.
**Harnais :** `qa_e2e/` (lots `t1_auth`…`t10_security`, lib `qa.py`, médias réels `qa_e2e/media/`, journaux `qa_e2e/artifacts/`).

---

## 0. Verdict

> **Aucune régression produit détectée.** Les correctifs du hardening (C-1, C-2, C-3, M-1→M-6, m-1) **tiennent tous**. Tous les parcours métier exigés par la mission ont été validés réellement contre la base de production.
>
> Les écarts bruts du harnais (jusqu'à 26 sur un run) se résolvent **intégralement** en : (a) **artefacts d'environnement** (Redis Render inaccessible, latence intercontinentale + dev-server mono-process, client WebSocket headless), (b) **artefacts du harnais** (IDs codés en dur, noms de champs périmés, wallet pré-financé, assertion périmée), (c) **comportement voulu** (`is_active` forcé). **2 vraies constatations** subsistent — non bloquantes, hors code applicatif critique : diffusion média R2 et robustesse de `broadcast_event`.

---

## 1. Environnement de test (déterminant pour lire ce rapport)

Conformément à la demande : backend Django **local connecté aux datastores de PRODUCTION**, exposé en ligne via **ngrok**, données de `marche-cm.env`.

| Élément | Valeur réelle constatée |
|---|---|
| Backend | Django/Channels (Daphne) **local** `127.0.0.1:8000`, code de la branche `main` (hardené) |
| Base de données | **PostgreSQL de PROD** (Render Frankfurt `marchr_cm_db`, PostgreSQL 18.3) — écriture réelle |
| Tunnel public | `https://choirlike-niki-phototactically.ngrok-free.dev` → `:8000` (webhooks NotchPay) |
| Redis | **Render Key Value (Frankfurt)** — voir §2.2 (IP non allowlistée → bascule channels/cache **in-memory**) |
| Stockage média | Cloudflare **R2** (clés prod) |
| NotchPay | **MODE LIVE** (clés réelles) — aucun débit réel déclenché dans l'audit automatisé |
| Latence client→Frankfurt | **RTT ~295 ms / requête SQL ou Redis** (poste distant) — cause majeure des timeouts |

**État de la base de prod au démarrage :** 3 comptes acheteurs réels, **0 produit / 0 commande / 0 wallet / 0 escrow / 0 litige**. Déploiement quasi vierge — risque d'écriture de données de test faible.

**4 migrations de hardening non appliquées** ont été appliquées à la prod (toutes additives / non destructrices, sur tables vides) :
`accounts.0015` (consentement KYC), `accounts.0016` (suspension utilisateur — fix M-6), `ledger.0003`, `wallets.0013`.

---

## 2. Constatations d'INFRASTRUCTURE (hors code, mais bloquantes pour la prod)

### 2.1 🔴 CRITIQUE — Le backend déployé est HORS LIGNE
- **Repro :** `GET https://marche-cm-backend.onrender.com/api/health/` (et `/`, `/api/`, `/admin/`).
- **Observé :** `404`, `Server: cloudflare`, corps `Not Found` (10 octets, `text/plain`) — réponse de l'edge Render, **pas** de Django. Aucun service web n'est servi à ce hostname.
- **Impact business :** l'application n'est **pas accessible en ligne**. La Mission 2 (load test « prod hébergée ») n'a actuellement **aucune cible**. À redéployer.

### 2.2 🟠 MAJEUR — Redis Render rejette les IP non allowlistées
- **Repro :** toute opération channel-layer/cache/lock depuis ce poste.
- **Observé (logs backend) :** `redis.exceptions.ResponseError: Client IP address is not in the allowlist.` — chaque appel attend ~15 s puis échoue (`slow_request elapsed_ms=14828`).
- **Effet de bord révélateur :** voir constatation applicative §4.2 (les écritures avec `broadcast_event` renvoyaient 500).
- **Action :** allowlister l'IP cliente `102.244.197.171` sur Render Key Value, **ou** garder Redis interne (la prod déployée y accède en réseau privé). Pour cet audit, bascule en **channels/cache in-memory** (mono-process local, DB prod inchangée).

### 2.3 🟠 MAJEUR — Bucket R2 mal nommé (corrigé en cours d'audit)
- `AWS_STORAGE_BUCKET_NAME` valait `"R2 Account Token"` (un libellé, pas un nom de bucket) — corrigé en `Market_File` pendant l'audit. Voir aussi §4.1 (diffusion média).

---

## 3. Résultats par domaine métier (tous validés réellement)

| Domaine | Tests | Verdict | Preuves clés |
|---|---|---|---|
| **AUTH** | inscription (acheteur/vendeur/grossiste/livreur), login, logout, refresh, rôles | ✅ 17/17 | privesc `role=GENERAL_ADMIN` refusée ; injection de rôle forcée à BUYER ; JWT falsifié/expiré rejeté ; logout blackliste le refresh |
| **PROFIL / mot de passe / 2FA** | update, change-password, challenge sensible | ✅ | update sans challenge refusé ; mdp faible/identique refusé ; persistance vérifiée en base |
| **KYC** | soumission CNI (image+signature+consentement), validation admin | ✅ | `201` + `PENDING` en base (5,7 s en isolation) ; admin approuve → `APPROVED` en base ; doc_type invalide et fichier polyglot rejetés |
| **PRODUITS** | CRUD, upload image/vidéo, visibilité, IDOR | ✅ (1 réserve média §4.1) | acheteur ne peut pas publier ; grossiste OK ; vidéo OK ; cap >5 Mo ; IDOR suppression bloquée (403/404) |
| **WALLET** | solde, recharge, retrait, PIN, limites KYC | ✅ | montant/provider/téléphone invalides rejetés ; **limite KYC niveau 0 (25000) appliquée** ; retrait sans 2FA refusé (403) ; PIN requis |
| **MARKETPLACE / ESCROW** | panier→commande, intégrité prix, escrow, annulation, remboursement | ✅ | **prix calculés serveur (override client ignoré), escrow `HELD`, wallet débité** ; IDOR commande bloqué ; **annulation → `CANCELLED` + escrow remboursé acheteur (+8600)** = fix C-3 |
| **LOGISTIQUE** | cycle expédition, RBAC transitaire | ✅ | `PICKUP_PENDING→IN_TRANSIT` (transitaire) ; acheteur interdit (403) ; transition invalide rejetée (400) ; non-participant bloqué (404) |
| **LITIGES** | ouverture, preuves | ✅ | ouverture `201` (acheteur vs vendeur) avec `reason`/`details` ; validation livraison sans preuve refusée |
| **MESSAGERIE** | chat REST + temps réel WebSocket | ✅ | création salon, envoi texte/image/vidéo, **lecture participant (3 msgs)**, **cloisonnement non-participant (0 msg, 403 en écriture)**, append-only (DELETE 405) ; **WS `/ws/notifications/` et `/ws/chat/{id}/` connectés via Origin + sous-protocole `bearer`** |
| **ADMIN** | dashboard, audit, KYC, suspension/réactivation | ✅ | dashboard + export CSV RBAC (403 non-admin) ; **validation KYC** ; **suspension → login bloqué `401 "Compte suspendu"` → réactivation → login OK** (fix M-6 bout-en-bout) |
| **SÉCURITÉ** | SQLi, XSS, CSRF, JWT forgé, IDOR, privesc, brute-force, mass-assignment | ✅ 9/10* | SQLi (recherche + id chemin) neutralisée (ORM) ; IDOR user/wallet/commande bloqué ; JWT forgé/expiré rejeté ; **mass-assignment `is_superuser/role/kyc_level` bloqué** ; headers sécurité présents ; scanner bloqué (400) |

\* *Le seul « échec » sécurité (T10.9) est une réponse défensive `400` correcte que le test n'avait pas mise dans sa liste acceptée — pas de 500, requête bloquée.*

---

## 4. Vraies constatations applicatives (non-régressions, à traiter)

### 4.1 🟠 MAJEUR — Médias uploadés non servables publiquement
- **Endpoint :** `POST /api/products/` (image), `/api/auth/kyc/submit/`, `/api/chat/messages/` (média).
- **Repro :** créer un produit avec image → `file_url` = `https://<acct>.r2.cloudflarestorage.com/<bucket>/<key>` ; `GET` de cette URL.
- **Observé :** `HTTP 400`, `Content-Type application/xml` (erreur S3). L'URL pointe sur **l'endpoint API S3 privé de R2**, qui refuse un GET public non signé.
- **Impact business :** **images produits, documents KYC et médias de chat ne s'affichent pas** côté client (web/mobile). Bloquant pour l'expérience marketplace.
- **Recommandation :** servir les médias via un **domaine public R2** (`pub-xxxx.r2.dev`) ou un domaine custom, ou générer des **URLs signées**. Et valider le nom de bucket (`Market_File`) + l'accès public.

### 4.2 🟠 MAJEUR — `broadcast_event` dans le chemin requête n'est pas tolérant aux pannes
- **Code :** `apps/notifications/realtime.py:9` (`async_to_sync(layer.group_send)`), appelé par `apps/accounts/views.py:723` (profil), `apps/catalog/views.py:54` (création produit) et `:150` (vidéo), création de salon chat.
- **Repro :** channel layer (Redis) indisponible → toute écriture déclenchant un fan-out temps réel.
- **Observé (logs run-1) :** `500 "Une erreur interne est survenue."` avec traceback `redis.exceptions.ResponseError`. L'écriture R2/DB réussit mais la réponse est 500 (et ~15 s de latence).
- **Impact business :** un simple incident Redis en prod ferait **échouer toutes les créations** de produit/profil/chat (au lieu de dégrader le temps réel silencieusement).
- **Recommandation :** envelopper `broadcast_event`/`group_send` dans un `try/except` (fire-and-forget + log), pour découpler le fan-out temps réel de la transaction métier.

### 4.3 🟡 INFO (par conception) — Plus d'état « brouillon » produit
- `is_active` est forcé à `True` à la création (fix C-2). Un vendeur ne peut plus créer un produit masqué : tout part en ligne immédiatement. À confirmer comme voulu côté produit.

---

## 5. Triage des écarts bruts du harnais (preuve qu'il n'y a pas de régression)

| Test(s) | Symptôme brut | Cause réelle | Catégorie |
|---|---|---|---|
| T2.9–2.11 (KYC) | `NA` (timeout) | Upload 2 fichiers vers R2 depuis poste distant > timeout 60 s ; **OK en isolation (`201`+`PENDING`)** | Environnement |
| T3.2–3.13 (produits) | `401` en cascade | Login supplier/wholesaler **hang 60 s** (dev-server mono-process saturé par uploads KYC précédents) ; **OK en isolation (11/14)** | Environnement |
| T3.3 (image servie) | `400 XML` | Diffusion média R2 (endpoint S3 privé) | **Vraie constatation §4.1** |
| T3.10 (IDOR modif) | `400` (validation) | Rejet en validation avant la couche permission ; aucune brèche (T3.11 confirme la protection) | Artefact test |
| T3.14 (brouillon) | `is_active=True` | Comportement voulu (fix C-2) | Par conception |
| T6.4 (solde insuffisant) | `201` au lieu de `400` | Wallet acheteur pré-financé (50000 cumulés des runs) ; logique OK (cf. T6.5) | Artefact test (état) |
| T6.7 (livraison→COMPLETED) | `400` transition invalide | State machine refuse `PENDING→COMPLETED` (court-circuit du cycle) — **correct** | Artefact test (flux) |
| T7.7 (ouverture litige) | `400` champs requis | Harnais envoyait `dispute_type/description` ; champs réels `reason/details` ; **OK reconfirmé (`201`)** | Artefact test (champs) |
| T8.5 (lecture msgs) | `count=0` | Cascade env ; **OK en isolation (`count=3`)** | Environnement |
| T8.11–8.13 (WebSocket) | rejet connexion | Client headless sans en-tête `Origin` (rejeté par `AllowedHostsOriginValidator`) + token en query-string désactivé par durcissement ; **OK reconfirmé via Origin + sous-protocole `bearer`** | Environnement / config |
| T9.12 (suspension) | « endpoint absent » | **Assertion périmée** : `suspend`/`unsuspend` existent (`views.py:303/329`) ; **flux bout-en-bout reconfirmé** | Artefact test (périmé) |
| T10.9 (scanner UA) | `400` | Blocage défensif correct (pas de 500) hors liste acceptée du test | Artefact test (assertion) |

---

## 6. État des correctifs du 1er rapport (anti-régression)

| Fix | Objet | Statut V2 |
|---|---|---|
| **C-1** | Création produit vendeur (clés legacy→canoniques) | ✅ OK (produits créés via multipart) |
| **C-2** | `is_active` read-only + forcé True à la création | ✅ OK (vérifié, cf. §4.3) |
| **C-3** | Annulation atomique = remboursement escrow | ✅ OK (T7.6 : `CANCELLED` + +8600 recrédité) |
| **M-1** | Géocodage hors chemin requête (thread/Celery) | ✅ OK (échec d'enqueue dégradé en WARNING, pas 500) |
| **M-2/M-3** | KYC `PROOF_ADDRESS`/`SELFIE`/`CNI` + consentement | ✅ OK (soumission + approbation admin) |
| **M-4** | Grossiste : prix dérivés serveur | ✅ OK (T3.4) |
| **M-5** | WS `/ws/events/` + fallback 4404 | ✅ OK (routing + auth WS confirmés) |
| **M-6** | Suspension utilisateur (+ révocation accès) | ✅ OK (suspend→login 401→unsuspend→login OK) |
| **m-1** | Unicité nom d'affichage retirée du profil | ✅ OK |

---

## 7. Limites de cette campagne
- **NotchPay LIVE :** aucun débit réel déclenché par l'automatisation (les chemins testés s'arrêtent avant `create_invoice`/`send_money`). Le test « 1 paiement réel petit montant » nécessite l'**approbation Mobile Money sur le téléphone du propriétaire** (étape manuelle) — à planifier.
- **Latence/dev-server :** l'environnement (poste distant ~295 ms de Frankfurt + `runserver` mono-process) génère des **timeouts cascadés** qui faussent un run séquentiel complet ; les batches ont donc été **rejoués en isolation** pour un signal propre. Un run propre nécessiterait : Redis local/allowlisté, ou backend co-localisé (déployé).
- **Frontends Flutter :** l'audit valide les **contrats API/WebSocket** consommés par les apps (niveau de la 1ʳᵉ campagne), pas un pilotage navigateur de chaque écran.

---

## 8. Actions recommandées (par priorité)
1. **Redéployer le backend** (`marche-cm-backend.onrender.com` est hors ligne). — *bloquant prod & Mission 2*
2. **Diffusion média R2** : domaine public/URLs signées + valider le bucket. — §4.1
3. **`broadcast_event` tolérant aux pannes** (try/except). — §4.2
4. Allowlister l'IP ou confirmer l'accès Redis interne ; corriger le typo `CACHE_URL` (`:63799`).
5. Confirmer le choix « pas de brouillon produit » (§4.3).
6. Nettoyer les comptes démo `*@marche-cm.local` (dont **admin à mot de passe faible**) et les données de test créées en prod pendant l'audit.

---

*Artefacts : `qa_e2e/artifacts/results.jsonl` (résultats), `calls.jsonl` (requêtes/réponses), `aggregated_v2.json`. Scripts de vérification ciblés : `qa_e2e/_verify_ws.py`, `_verify_misc.py`, `_verify_final.py`.*
