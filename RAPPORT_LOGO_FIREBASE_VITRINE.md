# RAPPORT — Logo unifié, Firebase, et téléchargement vitrine (vérifié)

**Date** : 2026-06-10
**Méthode** : exécutions réelles (rasterisation, génération d'icônes, builds APK + web, build du site). Aucune affirmation non vérifiée.

---

## 1. Nouveau logo (logo_4_cercle_moderne.svg) sur les 4 apps

- SVG rasterisé en PNG **1024×1024** via Chrome headless (dégradés + ombre + texte rendus fidèlement).
- `assets/app_icon_source.png` remplacé dans les **4 apps**, puis `flutter_launcher_icons` régénéré (Android/iOS/Web).
- **Avant** : Driver/Admin affichaient l'icône Flutter par défaut ; Seller/Clients l'ancien wordmark « Central Market ».
- **Après** : les 4 apps affichent le cercle vert « M · MARCHÉ CM » (vérifié visuellement sur les `ic_launcher.png`).

## 2. Firebase intégré dans Clients / Driver / Admin

Projet partagé **`marche-cm`** (n° 355585940733). Pattern uniforme : init **gardée** (try/catch) pour qu'un échec (CDN web injoignable en local) ne blanchisse jamais l'app.

| App | Android | Web | iOS | Token FCM → backend |
|---|---|---|---|---|
| **Clients** | ✅ (google-services.json + plugin déjà câblés ; appId `…a0e6e19a…`) | ✅ (config web marche-cm) | 🟡 scaffold (throw guardé) | via `http` + `AuthTokenManager` → `/api/auth/fcm-token/` |
| **Driver** | ✅ (appId `…9c966924…`) | ✅ | 🟡 scaffold | via `DriverDioClient.dio` |
| **Admin** | 🟡 non enregistré (console web) | ✅ | 🟡 | via `SecureDioClient.dio` |

Fichiers ajoutés par app : `lib/firebase_options.dart`, `lib/core/push_notification_service.dart`, deps `firebase_core`/`firebase_messaging` dans `pubspec.yaml`, init dans `main.dart`.

**Vérifié** :
- `flutter analyze` = **0 issue** sur Clients, Driver, Admin (après intégration).
- `flutter build web --release` (Clients) = **✅ Built** ; `firebase` est référencé dans `main.dart.js` → l'intégration web compile et est bundlée.

**À compléter (credentials côté console — hors de portée ici)** :
- **iOS** : enregistrer chaque app iOS dans la console Firebase `marche-cm`, déposer `ios/Runner/GoogleService-Info.plist`, configurer une **clé APNs**, puis remplir le bloc `ios` de `firebase_options.dart`.
- **Push web** : ajouter une **clé VAPID** + `web/firebase-messaging-sw.js` (le core web fonctionne déjà ; seul le `getToken()` web est différé).
- **Admin natif** : enregistrer une app Android/iOS si un APK admin doit recevoir du push (aujourd'hui c'est une console web).

## 3. Builds release APK (exécutés réellement)

| App | Taille | Signature |
|---|---|---|
| Vendeur (`frontend/app`) | **60,0 MB** | clé upload (release) |
| Acheteur (`frontend/Clients`) | **60,0 MB** | clé upload (release) |
| Livreur (`frontend/Driver App/app`) | **52,7 MB** | **debug** (sideload OK, pas Play) |
| Admin (`frontend/admin/project`) | **49,2 MB** | **debug** ; `applicationId = com.example.project` (placeholder) |

Toutes buildées avec le nouveau logo + Firebase. APK debug-signés = installables par téléchargement direct, mais **à re-signer avec une vraie clé pour le Play Store**.

## 4. Site vitrine — téléchargement direct + icônes

- APK copiés dans `MarketCM_vitrineSite/public/downloads/` : `marche-cm-acheteur.apk`, `marche-cm-vendeur.apk`, `marche-cm-livreur.apk`, `marche-cm-admin.apk`.
- `src/data/site.ts` : ajout des chemins `apk` par rôle (`config.stores.*.apk`).
- `src/components/sections/Apps.tsx` : bouton **« Télécharger pour Android (APK) »** (téléchargement direct, attribut `download`) ; App Store marqué « bientôt » ; icône de chaque carte d'app = **logo_4** (`/app-logo.svg`).
- `public/favicon.svg` remplacé par l'emblème logo_4 (cercle vert « M »).
- **Contact** : WhatsApp `+237695605502`, email `kerianluka@gmail.com` (`src/data/site.ts`).
- **Vérifié** : `tsc --noEmit` = 0 erreur ; `npm run build` = ✅ (built 1,85 s) ; les 4 APK sont présents dans `dist/downloads/`.

> Choix : la **console Admin** n'est PAS exposée sur une carte publique (c'est un outil interne) ; son APK est néanmoins présent dans `downloads/`. Le wordmark « MarketCM » de la Navbar est conservé (marque entreprise) — seules les icônes d'app + favicon passent au logo_4.

## 5. Risques / à savoir

- **Poids Git** : ~230 MB d'APK dans `public/downloads/`. Pour la prod, préférer **Git LFS** ou un hébergement d'assets (release GitHub / CDN / S3) plutôt que de versionner les binaires.
- **Driver/Admin debug-signés** : OK pour téléchargement direct, à re-signer (keystore upload) avant publication Play.
- **Admin `com.example.project`** : à renommer en identifiant réel si l'APK admin doit être distribué.
- **iOS / push web** : voir §2 (credentials requis).

## 6. Fichiers modifiés/ajoutés (récapitulatif)

- 4 apps : `assets/app_icon_source.png` + icônes générées (mipmap/ios/web)
- Clients : `pubspec.yaml`, `lib/firebase_options.dart` (nouveau), `lib/core/push_notification_service.dart` (nouveau), `lib/main.dart`
- Driver : idem (+ retrait du commentaire « Firebase retiré »)
- Admin : idem (web-only options)
- Vitrine : `src/data/site.ts`, `src/components/sections/Apps.tsx`, `public/favicon.svg`, `public/app-logo.svg` (nouveau), `public/downloads/*.apk` (4)

*Rapport basé sur exécutions réelles : analyze ×3 (0 issue), 4 builds APK, 1 build web, 1 build site.*
