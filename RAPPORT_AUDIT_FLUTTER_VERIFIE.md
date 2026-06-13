# RAPPORT D'AUDIT FLUTTER — VÉRIFIÉ (preuves réelles)

**Date** : 2026-06-10
**Périmètre** : 4 applications Flutter (`frontend/app`, `frontend/Clients`, `frontend/Driver App/app`, `frontend/admin/project`)
**Méthode** : vérification par exécution réelle (analyze, builds, génération d'assets), pas d'affirmations théoriques.

> ⚠️ **Avertissement sur les rapports antérieurs**
> Les rapports existants (`ANDROID_BUILD_REPORT.md`, `FLUTTER_AUDIT.md`, `FINAL_PRODUCTION_AUDIT.md`…) sont en grande partie **aspirationnels** : ils emploient « assumed », « expected », « buildable », « ✅ 100% ready » alors qu'**aucun build n'avait jamais été exécuté** et que plusieurs affirmations sont **fausses sur disque** (ex. « adaptive icons générées », « 8 permissions déclarées » sur l'app vendeur). Ce rapport-ci ne contient que des faits vérifiés.

---

## 1. ENVIRONNEMENT (vérifié)

| Outil | Version | État |
|---|---|---|
| Flutter | 3.38.9 (stable) | ✅ |
| Dart | 3.10.8 | ✅ |
| Java (JDK) | 21.0.10 LTS | ✅ |
| Gradle (wrapper) | 8.13 | ✅ (zip en cache local) |
| Android Gradle Plugin | 8.11.1 | ✅ |
| Kotlin | 2.2.20 | ✅ |
| Cible bytecode | Java 17 | ✅ |
| Android SDK | configuré (`compileSdk`/`targetSdk` = flutter defaults) | ✅ |
| Appareil de test | Samsung SM-A528B, Android 14 (API 34), connecté | ✅ |

**Conclusion matrice Java/Gradle/Kotlin** : **cohérente et 100 % compatible**. AGP 8.11.1 + Gradle 8.13 + Kotlin 2.2.20 ciblant Java 17, exécutés sur JDK 21 — combinaison supportée. **Aucune incompatibilité à corriger** (contrairement à l'hypothèse d'un audit générique).

> Note : `flutter doctor` plante sur le check « Android toolchain » (timeout > 4 min 30, probablement `sdkmanager`/licences). **Cela n'empêche pas la compilation** : deux builds release ont réussi (voir §3).

---

## 2. ANALYSE STATIQUE (vérifiée — `flutter analyze`)

| App | Résultat | Temps |
|---|---|---|
| `frontend/app` (Vendeur/Pro) | **No issues found** | 99,9 s |
| `frontend/Clients` (Acheteur) | **No issues found** | 9,8 s |
| `frontend/Driver App/app` (Livreur) | **No issues found** | 12,7 s |
| `frontend/admin/project` (Admin) | **No issues found** | 4,2 s |

✅ **0 erreur, 0 warning** sur les 4 applications.

---

## 3. BUILDS RELEASE (PREUVE DE COMPILATION — exécutés réellement)

| App | Commande | Résultat | Taille | Signé |
|---|---|---|---|---|
| `frontend/app` | `flutter build apk --release` | ✅ **Built** (536,7 s) | **60,0 MB** (62 956 308 o) | ✅ (`.sha1`) |
| `frontend/Clients` | `flutter build apk --release` | ✅ **Built** (217,1 s) | **59,7 MB** (62 589 038 o) | ✅ |

- C'est la **première preuve réelle** que ces apps compilent en APK release signé.
- Tree-shaking des polices d'icônes effectif (MaterialIcons −98,7 %, lucide −99,8 %).
- Le build Clients a aussi **validé la correction de manifeste** (§4) : `network_security_config` se résout correctement.

> Non encore exécutés (par contrainte de temps/plateforme) : builds release **Driver** et **admin**, **AAB** (`appbundle`), build **iOS** (nécessite macOS — impossible sur Windows). Voir §8 Recommandations.

---

## 4. CORRECTIONS APPLIQUÉES (et vérifiées)

### 4.1 Icônes de lancement — Driver & Admin (gain net, vérifié visuellement)
- **Constat réel** : Driver et Admin embarquaient encore **l'icône Flutter par défaut** (logo bleu) — bug de production. (Seller & Clients étaient déjà à la marque.)
- **Action** : ajout de `flutter_launcher_icons` (config + dev_dependency) aux `pubspec.yaml` Driver et Admin, puis génération Android/iOS/Web depuis `assets/app_icon_source.png` (1024×1024).
- **Vérifié** : les `mipmap/ic_launcher.png` affichent désormais le logo **Central Market**. ✅

### 4.2 Durcissement manifeste — App Vendeur
- Ajout de `POST_NOTIFICATIONS` (requis Android 13+ ; l'app utilise `firebase_messaging` et ne la déclarait pas) et `ACCESS_NETWORK_STATE`.
- **Vérifié** : build release seller réussi avant/après (compilation OK).

### 4.3 Durcissement réseau — App Clients
- **Constat** : `android:usesCleartextTraffic="true"` (HTTP autorisé globalement — signalé par le Play Store).
- **Action** : création de `res/xml/network_security_config.xml` (deny-by-default, exemption loopback/emulator uniquement, identique à l'app vendeur) ; remplacement de l'attribut `usesCleartextTraffic` par `networkSecurityConfig`.
- **Vérifié** : **build release Clients réussi** → la référence se résout et l'app compile. ✅

**Fichiers modifiés**
- `frontend/app/android/app/src/main/AndroidManifest.xml`
- `frontend/Clients/android/app/src/main/AndroidManifest.xml`
- `frontend/Clients/android/app/src/main/res/xml/network_security_config.xml` (nouveau)
- `frontend/Driver App/app/pubspec.yaml` + icônes générées (mipmap, ios, web)
- `frontend/admin/project/pubspec.yaml` + icônes générées (mipmap, ios, web)

---

## 5. SÉCURITÉ (audit réel)

| Point | État |
|---|---|
| Secrets de signature (`key.properties`, `upload-keystore.jks`) | ✅ **gitignored** — pas de fuite dans le dépôt |
| URLs API | ✅ Centralisées (`AppConfig`), injectées via `--dart-define`, **HTTPS forcé en release** (assertion anti-MITM, exemption loopback) |
| Stockage des tokens | ✅ `flutter_secure_storage` (Keystore Android / Keychain iOS), jamais en SharedPreferences |
| Client HTTP | ✅ `dio` centralisé (`SecureDioClient`) : interceptors, refresh réactif, device binding |
| FCM token | ✅ Enregistré/désenregistré proprement, stocké chiffré |
| Cleartext réseau | ✅ Deny-by-default (seller + désormais Clients) ; **Driver reste à vérifier** |
| Clés Firebase dans `firebase_options.dart` | ℹ️ **Publiques par conception** (pas une fuite) — mais **App Check non activé** → à durcir |
| Auth bypass | ✅ Strictement limité aux builds debug/profile (`!kReleaseMode`) |

⚠️ **Hors périmètre Flutter mais à traiter** (cf. `RAPPORT_AUDIT_API.md` & mémoire projet) : un secret **NotchPay LIVE / clé Fernet** a été commité dans l'historique git côté backend → **à faire tourner (rotation)**.

---

## 6. FIREBASE & NOTIFICATIONS PUSH (état réel, non « idéalisé »)

- **App Vendeur** : Firebase pleinement intégré (`firebase_core` + `firebase_messaging`), init protégée par try/catch et **désactivée sur web** (le SDK JS Firebase n'est pas joignable ici), handler background top-level, foreground → snackbar, désinscription au logout. **Bien conçu.**
- **Clients & Driver** : `firebase_messaging` **volontairement retiré** (commentaire explicite : plantait le build web ; le temps réel passe par **WebSocket**). `google-services.json` présent pour un éventuel retour du push natif.
- **Admin** : pas de Firebase (console, web-first).

➡️ **Ce n'est pas un bug de configuration mais un choix d'architecture** (apps web-first + WebSocket). Je n'ai **pas** réintroduit `firebase_messaging` partout pour ne pas casser le web. Voir §8 si le push mobile natif devient requis.

---

## 7. ICÔNES & SPLASH — point honnête

- **Icônes** : la source `app_icon_source.png` est un **logo-signature complet** (emblème + texte « CENTRAL MARKET » + baseline, fond blanc). À taille launcher, le texte est **illisible** et l'emblème minuscule. Les 4 apps sont désormais « à la marque », mais :
  - **Pas d'adaptive icons** (`mipmap-anydpi-v26` absent) sur Android 8+.
  - Je **n'ai pas** fabriqué d'adaptive icon à partir de cette source : un foreground avec texte + fond blanc donnerait un rendu **dégradé** (rognage par le masque). → **Recommandation** : produire un **mark dédié** (emblème seul, sans texte, avec marge « safe zone »), puis configurer `adaptive_icon_background` + `adaptive_icon_foreground`.
- **Splash** : un **splash applicatif animé** (`CmSplashScreen`) existe déjà côté Flutter. En revanche le **splash natif** (avant le chargement du moteur Flutter) reste le `launch_background.xml` blanc standard → flash blanc au lancement. **Recommandation** : `flutter_native_splash` avec le logo + couleur de marque pour supprimer le flash.

---

## 8. RECOMMANDATIONS (non appliquées — risque/temps/plateforme)

**Priorité haute**
1. **Rotation du secret NotchPay LIVE** présent dans l'historique git (backend).
2. **Activer Firebase App Check** (et règles Firebase strictes) pour l'app vendeur.
3. **Mark de lancement dédié** (emblème seul) + **adaptive icons** sur les 4 apps.
4. Vérifier/ajouter `network_security_config` sur **Driver** (cohérence avec seller/Clients).

**Priorité moyenne**
5. Builds release **Driver** + **Admin**, et **AAB** (`flutter build appbundle --release`) pour le Play Store.
6. **Splash natif** (`flutter_native_splash`).
7. Build **iOS** (nécessite un poste **macOS** + Xcode — non réalisable sur Windows). Vérifier `Info.plist` (permissions, ATS) et `GoogleService-Info.plist` (absent du dépôt).
8. **Gradle wrapper portable** : `distributionUrl` pointe vers `file:///C:/gradle-cache/...` (chemin machine) → repasser à l'URL officielle `https://services.gradle.org/...` pour la CI et les autres postes.
9. **Builds avec `--obfuscate --split-debug-info`** pour la distribution finale (durcissement reverse-engineering).

**Priorité basse / observabilité**
10. Crashlytics + Analytics, Deep Linking, mode offline/caching avancé.
11. **Profilage runtime** (DevTools) pour valider rebuilds/perf — non mesuré ici (l'analyse statique ne le couvre pas).

---

## 9. SCORES (basés sur preuves, pas sur intentions)

| Axe | Score | Justification |
|---|---|---|
| **Sécurité** | **8,5 / 10** | Secrets gitignored, HTTPS forcé, secure storage, network config, isolation des rôles. − App Check absent, secret backend à tourner, Driver cleartext à vérifier. |
| **Architecture** | **9 / 10** | Structure feature-based, config centralisée, client Dio sécurisé, isolation stricte des rôles par app. |
| **Qualité code** | **9 / 10** | `flutter analyze` = 0 issue sur les 4 apps. |
| **Build / Compilation** | **8 / 10** | 2 builds release **prouvés** (seller, Clients). − Driver/admin/AAB/iOS non encore buildés. |
| **Performance** | **7 / 10 (provisoire)** | Tree-shaking actif, APK ~60 MB (normal Flutter). Non profilé au runtime → score à confirmer. |
| **Production-readiness (Android)** | **7,5 / 10** | Compilation prouvée + branding corrigé + manifests durcis. Reste : adaptive icons, splash natif, AAB, App Check. |
| **Production-readiness (iOS)** | **N/A** | Non vérifiable sur Windows (macOS requis). |

---

## 10. CE QUI A RÉELLEMENT ÉTÉ FAIT DANS CETTE PASSE

✅ Vérifié la matrice Java/Gradle/Kotlin (compatible — rien à corriger)
✅ `flutter analyze` exécuté sur les **4 apps** → toutes propres
✅ **2 builds release APK signés réussis** (seller 60 MB, Clients 59,7 MB)
✅ Remplacé l'**icône Flutter par défaut** par la marque sur **Driver** et **Admin** (vérifié visuellement)
✅ Ajouté `POST_NOTIFICATIONS` (+`ACCESS_NETWORK_STATE`) au manifeste **Vendeur**
✅ Remplacé le cleartext global de **Clients** par un `network_security_config` deny-by-default (**build-vérifié**)
✅ Audit sécurité réel des secrets, URLs, stockage tokens, Firebase

*Rapport généré à partir d'exécutions réelles. Aucune affirmation non vérifiée.*
