# RESET — État des 10 améliorations & reste à faire

_Dernière mise à jour : 2026-06-13 — branche `aws-infra`_

Ce document résume l'avancement des 10 points demandés et **ce qui reste à faire**
avant mise en production.

---

## ✅ Réalisé dans cette phase

| # | Point | État | Détail |
|---|-------|------|--------|
| 1 | Compression vidéo | ✅ | Rendue *fail-safe* : `video_compression_service.dart` enveloppé dans try/catch + `.timeout(3 min)`, retourne le fichier original en cas d'échec (plus de blocage). |
| 2 | PIN wallet | ✅ | **Suppression totale**. Backend `WalletPinView` → 410 Gone. Retrait/envoi protégés par le **code OTP email** (`wallet.withdraw`). PIN retiré des 4 apps (pages wallet, send, withdraw, dialogs) + libellés UI nettoyés. Colonnes DB conservées (non destructif). |
| 3 | KYC livreur bloquant | ✅ | Cause racine = MIME `octet-stream` rejeté par le durcissement upload. Corrigé **côté client** (déclaration MIME concrète à l'upload) sans affaiblir le backend. Erreurs serveur DRF désormais remontées (`driver_dio_client._serverDetail`). |
| 4 | Transitaire → Livreur | ✅ | **Libellés uniquement**. Tous les textes user-facing « Transitaire » → « Livreur » (4 apps + messages backend). Clé technique `TRANSIT_AGENT` **conservée**. Migration `0018_alter_user_role` (label uniquement). Flux de devis inchangé. |
| 5 | Image dans le chat | ✅ | Rendu de l'image elle-même au lieu du lien (Clients + vendeur), tag `IMAGE`, ouverture via `url_launcher`. |
| 6 | Connexion directe après inscription | ✅ | Auto-login câblé : Clients, vendeur (page détaillée **+ onglet rapide**), Driver. Le backend renvoie les tokens (`_issue_session_tokens`). Admin = pas d'auto-inscription. |
| 7 | Design vendeur | ✅ | Login/inscription/wallet alignés sur le design system (Plus Jakarta Sans, palette verte `AppPalette`). Auto-login câblé sur l'onglet inscription inline. |
| 8 | Reset mot de passe | ✅ | Backend `password/reset/request/` + `confirm/` (code 6 chiffres PBKDF2, anti-énumération, anti-brute-force). Écrans dans les 4 apps. |
| 9 | Session persistante | ✅ | Persistance des tokens via `flutter_secure_storage` + restauration au démarrage. Clients équipé (`TokenRepository` + `restoreFromStorage`) ; vendeur/driver/admin déjà équipés. |
| 10 | Tout câbler back/front | ✅ | Chaque modification est connectée. Validation : `flutter analyze` = **0 issue ×4 apps**. Tests backend ciblés = **91 OK**. |

---

## ⏳ Reste à faire (avant prod)

### 1. Commit & redéploiement — **PRIORITAIRE**
- [ ] **Commit** de toutes les modifications (rien n'est encore committé sur cette session).
- [ ] **Appliquer la migration `0018_alter_user_role`** en production (`manage.py migrate`).
- [ ] **Redéployer le backend** AWS (sinon les nouvelles routes reset-password / 410 PIN / labels ne seront pas servies).
- [ ] Vérifier que les routes `password/reset/*` ne sont **pas bloquées par `AUTH_LOCKDOWN`** en prod (garde conditionnelle présente dans `urls.py`).

### 2. Vérifications fonctionnelles réelles (device + prod)
- [ ] **Envoi d'email reset** réellement reçu en prod. ⚠️ Bug latent connu : `fetch_env.sh` casse le `source` quand une valeur SMTP contient des espaces/chevrons → vérifier que SMTP est bien chargé.
- [ ] Tester le **parcours auto-login** après inscription sur device réel (Clients / vendeur / Driver).
- [ ] Tester l'**upload KYC livreur** sur device réel (le fix MIME ciblait `octet-stream`).
- [ ] Tester **retrait wallet** sans PIN (OTP email seul) bout-en-bout.
- [ ] Tester **image dans le chat** (envoi + rendu) sur device réel avec média servi (R2/S3).

### 3. Nettoyages optionnels (non bloquants)
- [ ] Migration destructive ultérieure pour supprimer `wallet_pin_hash` + `set_wallet_pin/check_wallet_pin` (actuellement dormants, conservés pour éviter une migration destructive immédiate). Tests modèle `tests_wave9` les exercent encore.
- [ ] Admin `configuration_page.dart` : le toggle « PIN wallet obligatoire » a été retiré ; vérifier qu'aucune autre vue admin ne le référence.
- [ ] Uniformiser les éventuels libellés « Transitaire » résiduels dans les **assets/docs** (le code Dart + Python est nettoyé ; les `.md`/PDF de specs ne le sont pas).

### 4. Hors-scope explicitement décidé
- Point 4 « le client choisit le livreur à l'achat » → **descopé** par décision produit (« libellés seulement »). Le flux de devis/assignation actuel est conservé.
- Point 9 « ~5 min » → implémenté comme **persistance de session** (secure storage + refresh), pas comme un timer de 5 min ; comportement plus robuste (la session survit à la fermeture de l'app).

### 5. Dette pré-existante (rappel, hors de cette phase)
- iOS / VAPID Firebase encore à finaliser (cf. mémoire logo/firebase).
- Voir `AUDIT/` : fixes infra (Celery, fuite S3/KYC, crash-loop Redis) à committer + redéployer.

---

## 🧪 Statut de validation

| Cible | Résultat |
|-------|----------|
| `flutter analyze` — vendeur (`app`) | ✅ No issues found |
| `flutter analyze` — Clients | ✅ No issues found |
| `flutter analyze` — Driver | ✅ No issues found |
| `flutter analyze` — admin | ✅ No issues found |
| Tests backend (ciblés wallets + accounts) | ✅ 91 OK |
| Tests backend (suite complète) | ✅ **332 OK** (`Ran 332 tests in 504s`) |

> Validation complète : 4 apps Flutter sans erreur d'analyse + suite backend complète verte (0 régression).
