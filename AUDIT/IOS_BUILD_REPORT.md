# IOS_BUILD_REPORT — MarketCM
**Date :** 2026-06-12

## Statut : ❌ NON VÉRIFIÉ (impossible sur cet environnement)

`flutter build ios` et `flutter build ipa` **ne peuvent pas être exécutés** : la machine d'audit tourne sous **Windows 11**. La compilation iOS exige impérativement :
- macOS + Xcode,
- un Apple Developer Account,
- des provisioning profiles + certificats de signature.

Aucune affirmation sur la compilation iOS ne peut donc être prouvée ici. Toute mention contraire dans d'anciens rapports est **aspirationnelle, pas vérifiée**.

## Action requise
Exécuter sur un poste macOS :
```
cd frontend/<app>
flutter build ios --release
flutter build ipa --release
```
pour chacune des 4 apps, puis valider signatures et provisioning dans Xcode avant soumission à l'App Store.
