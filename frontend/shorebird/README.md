# Shorebird — mises à jour Dart à chaud (4 apps Android)

Shorebird pousse du **code Dart compilé** sur les apps déjà installées, **sans
passer par le store ni réinstaller**. Le patch s'applique au prochain lancement.
C'est le levier qui rend « une fonctionnalité / un widget appliqué presque
instantanément » possible sur les 3 apps mobiles + le build Android de Clients.

## Apps gérées

| Nom court | Dossier | applicationId |
|-----------|---------|---------------|
| `app`     | `frontend/app`            | `com.marchecm.app` |
| `clients` | `frontend/Clients`        | `com.marche.clients` |
| `driver`  | `frontend/Driver App/app` | `com.marchecm.driver` |
| `admin`   | `frontend/admin/project`  | `com.example.project` ⚠️ placeholder |

## Limite à connaître (garde-fou obligatoire)

Shorebird ne pousse **que du Dart**. Si un changement touche le **natif** —
nouveau plugin, permission Android, bump de SDK/NDK, dépendance Gradle, icône,
`AndroidManifest` — il faut une **nouvelle release + redistribution** (APK sur le
site vitrine ou store), pas un patch.

➡️ À coupler avec un **forced-update** côté serveur (`min_supported_version`) pour
obliger les utilisateurs à récupérer le nouvel APK quand le natif change. Sans ça,
un patch Dart pourrait s'appliquer sur une base native incompatible.

## Mise en place (UNE fois — nécessite TES identifiants)

Ces 3 étapes passent par un compte Shorebird (OAuth navigateur) ; elles ne peuvent
pas être automatisées côté agent.

```bash
# 1) Installer la CLI (Windows PowerShell)
iwr -UseBasicParsing https://raw.githubusercontent.com/shorebirdtech/install/main/install.ps1 | iex

# 2) Se connecter (ouvre le navigateur)
shorebird login

# 3) Initialiser les 4 apps (crée chaque shorebird.yaml avec son app_id)
bash frontend/shorebird/init-all.sh
```

Puis **committer** les `frontend/*/shorebird.yaml` générés (ils contiennent
l'`app_id`, ce sont des identifiants publics, pas des secrets).

> Vérifie aussi que la version Flutter du projet (actuellement **3.38.9**) est
> supportée : `shorebird flutter versions list`. Shorebird gère sa propre copie de
> Flutter ; release et patch doivent utiliser la même.

## Workflow quotidien

```bash
# Nouvelle base patchable (à chaque changement natif OU montée de version)
bash frontend/shorebird/release.sh driver          # APK par défaut
bash frontend/shorebird/release.sh driver --artifact aab   # pour le Play Store

# Correctif/feature 100% Dart sur la dernière release -> instantané
bash frontend/shorebird/patch.sh driver
```

Règle simple : **`release`** quand le natif bouge ou pour publier une version ;
**`patch`** pour tout le reste (UI, logique Dart, fix). Un `patch` ne s'applique
qu'aux appareils déjà sur la `release` correspondante.

## CI (optionnel)

`.github/workflows/shorebird-patch.yml` permet de pousser un patch via
`workflow_dispatch`. C'est un **template** : câbler d'abord les secrets
`SHOREBIRD_TOKEN`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PROPERTIES`. Au
quotidien, le chemin local ci-dessus reste le plus simple (le keystore vit sur ta
machine).

## Points de vigilance spécifiques au projet

- **admin** est encore en `com.example.project` : à renommer (ex.
  `com.marchecm.admin`) **avant** la première `release` Shorebird, sinon l'app_id
  serait lié à un applicationId jetable.
- **Clients** est aussi distribué en **web** : Shorebird ne couvre pas le web. Le
  web reste mis à jour par déploiement CDN + rechargement.
- Distribution actuelle = **APK direct via le site vitrine** → `release` en `apk`
  est le défaut. Pas de review store à attendre : combiné aux patchs, le cycle est
  déjà très court.
