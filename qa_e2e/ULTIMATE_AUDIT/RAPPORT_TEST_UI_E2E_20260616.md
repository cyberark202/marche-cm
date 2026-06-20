# Rapport — Test UI E2E piloté (clics + saisie réels) — 2026-06-16/17

Campagne de test en pilotant réellement les interfaces (clic boutons, saisie texte,
upload fichiers) sur les **4 apps Flutter web** + backend Django local, jusqu'au
déroulé complet d'un **scénario métier international à escrow scindé** impliquant
les 4 acteurs (acheteur, vendeur, livreur, admin).

Captures : `qa_e2e/artifacts/pw/` (~40 PNG). Harnais : `qa_e2e/_pw_drive.py`
(+ fichiers d'actions `qa_e2e/acts/`).

---

## 1. Méthode validée (le point dur du projet)

Piloter Flutter web par automatisation s'est révélé impossible en mode `flutter run`
(debug/DWDS → page blanche : l'app charge 958 modules puis attend un handshake de
debug qui ne vient jamais sous navigateur automatisé). **Solution retenue, fiable :**

- **Build release statique** (`flutter build web --release --no-web-resources-cdn
  --dart-define=API_BASE_URL=http://127.0.0.1:8000`) servi par `python -m http.server`.
- **Playwright Chromium en mode HEADED** (le headless perd le contexte WebGL →
  CanvasKit ne peint pas). GPU réel = rendu correct + vraies captures.
- Interaction via l'**arbre de sémantique Flutter** (clic sur `flt-semantics-placeholder`
  « Enable accessibility ») + **locators Playwright** qui percent le shadow DOM
  (`get_by_label`, `get_by_text`), avec repli clic par coordonnées (`tap_xy`).
- Boot robuste (polling readiness + ré-activation sémantique + reload de secours)
  pour absorber la flakiness WebGL au démarrage.

Setup (non faisable par l'UI en local) : `NOTCHPAY_ENABLED=False` (décaissement
**simulé**, zéro argent réel), seed comptes, crédit wallet acheteur, vendeur en
pays étranger (force INTERNATIONAL), poids produit, livreur tarifé/exclusif.

---

## 2. Testé réellement via l'UI (clic + saisie)

| App | Port | Parcours piloté en UI | Résultat |
|-----|------|------------------------|----------|
| **Clients** (acheteur) | 5000 | Accueil → **login** (saisie email+mdp, boutons) → catalogue → **recherche** produit → **ajout panier** (badge +1) → panier → onglet **Commandes** → **« Valider réception »** | ✅ |
| **Driver** (livreur) | 5002 | **Inscription complète** (nom, tél, email, type véhicule, mdp) → auto-login → **wizard KYC 4 étapes** (type doc, **upload Recto + Permis** via file picker, envoi) | ✅ |
| **Admin** | 5003 | **Login** → dashboard → **Conformité KYC** → ouverture dossier livreur → **revue + validation des 2 documents** (checklist + « Valider ») | ✅ |
| **Pro** (vendeur) | 5001 | Build + service OK (login non requis pour le scénario : actions vendeur passives) | ⚙️ |

Preuves notables :
- Login acheteur → shell authentifié (Catalogue, nav Boutique/Vidéos/Messages/Commandes/Wallet/Profil).
- Inscription livreur → compte `id=33 livreur_e2e_test role=TRANSIT_AGENT` créé en base.
- Validation KYC admin → **`driver.e2e is_verified=True`** confirmé en base.

---

## 3. Scénario métier international — déroulé E2E (commande #6)

Acheteur CM commandant chez un vendeur étranger (CN) ⇒ `order_type=INTERNATIONAL`,
escrow **scindé** fournisseur + logistique. Décaissements en mode **simulé**.

| # | Acteur | Action | Voie | Résultat vérifié en base |
|---|--------|--------|------|--------------------------|
| 1 | Acheteur | Passe commande (produit, qté, **livreur**, mode AIR) | API du panier* | Order INTERNATIONAL, `SPLIT_LOCKED` ; escrow **FOURNISSEUR 5000** + **LOGISTIQUE 7000** LOCKED ; wallet acheteur **12 000 bloqués** |
| 2 | Livreur | Confirme l'achat fournisseur | service** | `SUPPLIER_VERIFIED`, escrow fournisseur `READY` |
| 3 | Livreur | Upload preuve d'achat | service** | preuve enregistrée (**anti-réutilisation** du hash vérifiée : 2ᵉ usage rejeté) |
| 4 | Admin | Valide le fournisseur | service** | escrow **FOURNISSEUR RELEASED** (4750 net vendeur + 250 commission), order `SHIPPING` |
| 5 | (livraison) | Marque livré | script | order `DELIVERED` |
| 6 | Acheteur | **« Valider réception »** | **UI Clients** | escrow **LOGISTIQUE RELEASED** (7000 → livreur), order **`COMPLETED`** |

État final : `Order 6 COMPLETED / escrow RELEASED`, les 2 escrows RELEASED, acheteur
débloqué de 12 000, payouts vendeur+livreur exécutés (simulés). **La logique métier
complète (escrow scindé, transitions d'états, double-entrée, commission, anti-fraude,
séparation des rôles) fonctionne de bout en bout.**

\* La carte-ligne du **panier ne se peint pas sur web** (Finding #4) → la commande a
été créée via **l'API exacte que le panier appelle** (`POST /api/orders/` même payload).
\*\* App principale Driver inatteignable en session automatisée (cf. Finding #5) et
actions escrow « niche » → exécutées via la **couche service exacte des endpoints**
(`logistics/views.py` → `OrderFinanceService`), avec vérification des fonds à chaque pas.

---

## 4. Anomalies trouvées (findings)

| # | Sévérité | App/zone | Problème | Statut |
|---|----------|----------|----------|--------|
| **1** | 🔴 Majeur | Clients (web) | Écran blanc au boot web : `await PushNotificationService.initialize()` (Firebase messaging) **pend** indéfiniment ; le `try/catch` ne protège pas d'un hang → `runApp()` jamais atteint. | **Corrigé** (garde `if(!kIsWeb)`, comme l'app Pro) |
| **2** | 🔴 Bloquant | Driver (build) | `onboarding_page.dart:91` : `MultipartFile.fromStream(..., length: file.size, ...)` — `length` passé en **nommé** alors qu'il est **positionnel** → **l'app Driver ne compilait pas**. | **Corrigé** (`file.size` en positionnel) |
| **3** | 🟡 À confirmer | Driver (web) | Upload KYC : un `[pageerror] Error` apparaît au submit, mais les 2 documents **sont bien créés** côté backend (admin a pu les valider). Probable bruit générique Flutter web, pas un échec réel. | À confirmer |
| **4** | 🟠 Majeur | Clients (web) | **Panier** : la carte-ligne (sélection transitaire + mode transport + récap) **ne se peint pas** sur web (corps du panier blanc, absent de l'arbre sémantique) ; seul le pied (total + bouton) s'affiche. Reproductible 2/2. Bloque la sélection du livreur → checkout impossible en UI web. | Ouvert |
| **5** | 🟡 Moyen | Driver (routage) | Accès à l'app principale livreur gardé par un flag **local** `DriverSecureStorage.isOnboarded()` (mis par `completeKyc()`), **indépendant du `is_verified` backend**. Après approbation KYC admin, le livreur reste renvoyé à l'onboarding tant que le flag local n'est pas posé (et il ne persiste pas entre sessions). | À arbitrer (produit) |

Observations métier saines (pas des bugs) : l'**anti-réutilisation de preuve** rejette
un justificatif déjà utilisé ; un **payout vers un bénéficiaire sans `phone_number`**
échoue et **gèle l'escrow en litige** (comportement protecteur correct).

---

## 5. Correctifs de code appliqués (NON committés)

1. `frontend/Clients/lib/main.dart` — import `kIsWeb` + Firebase init entourée de
   `if (!kIsWeb)` (déblocage boot web).
2. `frontend/Driver App/app/lib/features/auth/presentation/onboarding_page.dart` —
   `MultipartFile.fromStream(() => file.readStream!, file.size, ...)` (compile fix).

À relire et committer si validés. Les 2 sont des correctifs réels et minimes,
alignés sur les patterns existants du repo.

---

## 6. À restaurer après campagne

- `backend/marche-cm.local.env` : `NOTCHPAY_ENABLED` remis à **True** (était passé à
  False pour le mode simulé). Le backend en cours d'exécution garde le mode simulé
  jusqu'à son **redémarrage**.
- Données de test créées : commandes #5 (gelée/litige) et #6 (complétée), livreur
  `driver.e2e` (#33), vendeur passé en pays CN, divers profils transport désactivés.
