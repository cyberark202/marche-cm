#!/usr/bin/env bash
# Initialise Shorebird dans les 4 apps. À lancer UNE FOIS, après 'shorebird login'.
# Chaque 'shorebird init' crée l'app côté serveur Shorebird et génère un
# shorebird.yaml (avec app_id) à COMMITTER.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$DIR/_lib.sh"
require_shorebird

ROOT="$(frontend_root)"
for key in $ALL_APPS; do
  sub="$(resolve_app_dir "$key")"
  echo "=== shorebird init : $key  ($sub) ==="
  if [ -f "$ROOT/$sub/shorebird.yaml" ]; then
    echo "  déjà initialisé (shorebird.yaml présent) — ignoré."
    continue
  fi
  ( cd "$ROOT/$sub" && shorebird init )
done
echo
echo "OK. Pense à committer chaque frontend/*/shorebird.yaml généré."
