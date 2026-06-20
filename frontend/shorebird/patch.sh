#!/usr/bin/env bash
# Pousse un PATCH Dart instantané sur la dernière release d'une app.
# Le patch s'applique au prochain lancement de l'app, SANS réinstallation ni store.
# ⚠️ Dart uniquement : si tu as touché du code natif (plugin, permission, bump SDK,
#    dépendance Android), il faut une nouvelle release + redistribution, PAS un patch.
#
# Usage: ./patch.sh <app|clients|driver|admin> [--release-version <x.y.z+n>] [args shorebird...]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$DIR/_lib.sh"
require_shorebird

[ $# -ge 1 ] || { echo "Usage: $0 <app|clients|driver|admin> [args...]" >&2; exit 2; }
key="$1"; shift
sub="$(resolve_app_dir "$key")" || { echo "App inconnue '$key' (attendu: $ALL_APPS)" >&2; exit 2; }

ROOT="$(frontend_root)"
cd "$ROOT/$sub"
echo ">> shorebird patch android $* — $key ($sub)"
shorebird patch android "$@"
