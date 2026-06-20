#!/usr/bin/env bash
# Construit une RELEASE Shorebird (la base patchable) pour une app.
# Une release = un nouvel APK/AAB à distribuer (site vitrine ou store).
# Tant que tu restes sur cette release, tu peux pousser des patchs Dart instantanés.
#
# Usage: ./release.sh <app|clients|driver|admin> [--artifact apk|aab] [args shorebird...]
#   défaut: --artifact apk  (canal de distribution actuel = APK direct via le site)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$DIR/_lib.sh"
require_shorebird

[ $# -ge 1 ] || { echo "Usage: $0 <app|clients|driver|admin> [--artifact apk|aab] [args...]" >&2; exit 2; }
key="$1"; shift
sub="$(resolve_app_dir "$key")" || { echo "App inconnue '$key' (attendu: $ALL_APPS)" >&2; exit 2; }

# Artefact par défaut = apk, sauf si l'appelant fournit déjà --artifact.
artifact_args=(--artifact apk)
for a in "$@"; do [ "$a" = "--artifact" ] && artifact_args=(); done

ROOT="$(frontend_root)"
cd "$ROOT/$sub"
echo ">> shorebird release android ${artifact_args[*]:-} $* — $key ($sub)"
shorebird release android "${artifact_args[@]}" "$@"
