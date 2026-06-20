#!/usr/bin/env bash
# Helpers partagés pour les scripts Shorebird des 4 apps Flutter de Marché CM.
# Sourced par init-all.sh / release.sh / patch.sh.
set -euo pipefail

# Liste des noms courts d'apps gérées.
ALL_APPS="app clients driver admin"

# Nom court -> sous-dossier sous frontend/.
# (Les chemins avec espace — "Driver App" — sont volontairement non échappés ici ;
#  les appelants DOIVENT toujours guillemetter "$sub".)
resolve_app_dir() {
  case "$1" in
    app|buyer|seller) echo "app" ;;
    clients)          echo "Clients" ;;
    driver)           echo "Driver App/app" ;;
    admin)            echo "admin/project" ;;
    *) return 1 ;;
  esac
}

# Chemin absolu de frontend/ (ce fichier vit dans frontend/shorebird/).
frontend_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

require_shorebird() {
  if ! command -v shorebird >/dev/null 2>&1; then
    echo "ERREUR: CLI 'shorebird' introuvable." >&2
    echo "  Installer (Windows PowerShell):" >&2
    echo "    iwr -UseBasicParsing https://raw.githubusercontent.com/shorebirdtech/install/main/install.ps1 | iex" >&2
    echo "  Puis: shorebird login" >&2
    exit 127
  fi
}
