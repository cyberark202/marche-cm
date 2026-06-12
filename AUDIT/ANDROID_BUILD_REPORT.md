# ANDROID_BUILD_REPORT — MarketCM
**Date :** 2026-06-12 · **Flutter 3.38.9 stable** · **Preuve :** `flutter build apk --release` exécuté pour les 4 apps, APK vérifiés sur disque.

## 1. Résultats (exécutés)
| App | Commande | Durée Gradle | APK | Taille | Présent sur disque |
|---|---|---|---|---|---|
| Manager/Seller | `flutter build apk --release` | 613,9 s | `frontend/app/build/app/outputs/flutter-apk/app-release.apk` | **60,0 MB** | ✅ |
| Client | `flutter build apk --release` | 282,5 s | `frontend/Clients/.../app-release.apk` | **60,0 MB** | ✅ |
| Driver | `flutter build apk --release` | 357,4 s | `frontend/Driver App/app/.../app-release.apk` | **52,8 MB** | ✅ |
| Admin | `flutter build apk --release` | 37,2 s | `frontend/admin/project/.../app-release.apk` | **49,2 MB** | ✅ |

**4/4 builds release réussis, 0 erreur de compilation.**

## 2. Observations
- Tree-shaking des polices d'icônes appliqué (lucide/Cupertino/Material) — réduction 99 %+, comportement normal en release.
- Aucune dépendance manquante, aucun crash de build.

## 3. Signatures / appbundle / iOS — état honnête
- ⚠️ **Signature** : les APK sont signés avec la config du projet (debug/keystore selon `android/app/build.gradle`). ❌ NON VÉRIFIÉ qu'un keystore de **release de production** distinct soit configuré pour le Play Store — à confirmer avant publication.
- `flutter build appbundle --release` (.aab pour le Play Store) : **non lancé dans cette passe** (les APK release prouvent la chaîne de build ; l'AAB se génère à l'identique). Recommandé avant soumission.
- 🍎 **iOS** (`flutter build ios` / `ipa`) : ❌ **NON VÉRIFIABLE** — la machine d'audit est sous Windows ; iOS exige macOS + Xcode + provisioning profiles. À exécuter sur un poste macOS.
