#!/usr/bin/env python
"""Infra de test : alignement des écrans Flutter avec le backend Django.

But
---
Garantir que chaque endpoint REST appelé par les 4 applications Flutter
(`app`, `Clients`, `Driver App/app`, `admin/project`) correspond à une route
réellement servie par le backend. Détecte les *désalignements* :

  • MISSING_IN_BACKEND : un écran appelle `/api/...` qui n'existe pas côté
    serveur → bug garanti à l'exécution (404). C'est ce qui fait échouer le test.
  • UNUSED_BACKEND     : route backend jamais appelée par aucune app (info).

Source de vérité
----------------
Les routes sont introspectées directement depuis l'URLconf Django
(`config.urls`) — routeur DRF + `path()`/`re_path()` + `@action` — donc le
rapport reflète exactement ce qui est déployé, pas une doc qui peut dériver.

Usage
-----
    python qa_e2e/check_screen_backend_alignment.py
    python qa_e2e/check_screen_backend_alignment.py --json    # sortie JSON
Code de sortie : 0 si aucun MISSING_IN_BACKEND, 1 sinon (utilisable en CI).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "backend"
FRONTEND = ROOT / "frontend"

# Les 4 applications Flutter et leur racine `lib/`.
FLUTTER_APPS = {
    "app": FRONTEND / "app" / "lib",
    "Clients": FRONTEND / "Clients" / "lib",
    "Driver App": FRONTEND / "Driver App" / "app" / "lib",
    "admin": FRONTEND / "admin" / "project" / "lib",
}

REPORT_PATH = ROOT / "qa_e2e" / "SCREEN_BACKEND_ALIGNMENT.md"


# ─────────────────────────────────────────────────────────────────────────────
# 1) Routes backend (introspection URLconf)
# ─────────────────────────────────────────────────────────────────────────────
def _bootstrap_django() -> None:
    """Charge Django avec des valeurs d'env sûres pour l'introspection seule.

    On ne touche pas la base : seul l'import de l'URLconf est requis.
    """
    sys.path.insert(0, str(BACKEND))
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
    os.environ.setdefault("DEBUG", "1")
    os.environ.setdefault("SECRET_KEY", "introspection-only-not-a-secret")
    os.environ.setdefault("ALLOWED_HOSTS", "127.0.0.1,localhost")
    os.environ.setdefault("DB_ENGINE", "sqlite")
    os.environ.setdefault("NOTCHPAY_ENABLED", "False")
    import django  # noqa: WPS433 (import tardif volontaire)

    django.setup()


def _clean_fragment(pattern: str) -> str:
    """Nettoie un fragment de regex d'URL (^, $, \\Z) pour la concaténation."""
    frag = pattern
    if frag.startswith("^"):
        frag = frag[1:]
    for tail in ("\\Z", "$"):
        if frag.endswith(tail):
            frag = frag[: -len(tail)]
    return frag


_PARAM_RE = re.compile(r"\(\?P<[^>]+>[^)]*\)|\([^)]*\)")


def _to_template(combined_regex: str) -> str:
    """Convertit une regex d'URL combinée en gabarit lisible `/api/.../{param}/`."""
    template = _PARAM_RE.sub("{param}", combined_regex)
    # Déséchappe les caractères regex courants présents dans les chemins.
    template = template.replace("\\/", "/").replace("\\.", ".").replace("\\-", "-")
    return "/" + template.lstrip("/")


def collect_backend_routes() -> list[dict]:
    """Retourne [{template, match_regex}] pour chaque route feuille de l'API."""
    from django.urls import get_resolver
    from django.urls.resolvers import URLPattern, URLResolver

    routes: list[dict] = []

    def walk(resolver, prefix: str) -> None:
        for entry in resolver.url_patterns:
            frag = _clean_fragment(entry.pattern.regex.pattern)
            if isinstance(entry, URLResolver):
                walk(entry, prefix + frag)
            elif isinstance(entry, URLPattern):
                combined = prefix + frag
                # Ignore les routes-suffixe de format DRF (`.json`, etc.) et la
                # racine du routeur : ce ne sont pas des endpoints appelés par
                # une app, juste du bruit dans la liste "non référencées".
                if "(?P<format>" in combined or "<drf_format_suffix" in combined:
                    continue
                template = _to_template(combined)
                if not template.startswith("/api"):
                    continue
                if template in ("/api", "/api/"):
                    continue
                # Regex de correspondance : ancrée, barre finale optionnelle.
                body = combined
                if body.endswith("/"):
                    body = body[:-1] + "/?"
                try:
                    match_regex = re.compile("^/?" + body + "$")
                except re.error:
                    continue
                routes.append({"template": template, "match_regex": match_regex})

    walk(get_resolver(), "")
    # Déduplique par gabarit.
    seen, unique = set(), []
    for r in routes:
        if r["template"] in seen:
            continue
        seen.add(r["template"])
        unique.append(r)
    return unique


# ─────────────────────────────────────────────────────────────────────────────
# 2) Endpoints référencés par les écrans Flutter
# ─────────────────────────────────────────────────────────────────────────────
# Capture une chaîne littérale Dart commençant par /api/ jusqu'au guillemet.
_DART_ENDPOINT_RE = re.compile(r"""['"](/api/[^'"]*)['"]""")


def _normalize_frontend_path(raw: str) -> str:
    """Normalise un chemin Dart en gabarit : interpolations → {param}, sans query."""
    path = raw.split("?", 1)[0].split("#", 1)[0]
    path = re.sub(r"\$\{[^}]*\}", "{param}", path)   # ${expr}
    path = re.sub(r"\$[A-Za-z_][A-Za-z0-9_]*", "{param}", path)  # $var
    if not path.endswith("/") and "{param}" not in path.split("/")[-1]:
        # Laisse tel quel ; la correspondance gère la barre finale optionnelle.
        pass
    return path


def _candidate_for_match(template_path: str) -> str:
    """Remplace les {param} par une valeur (`1`) qui matche les regex backend."""
    return template_path.replace("{param}", "1")


def collect_frontend_endpoints() -> dict[str, list[dict]]:
    """Retourne {endpoint_template: [{app, file, line, raw}]}."""
    found: dict[str, list[dict]] = {}
    for app_name, lib_dir in FLUTTER_APPS.items():
        if not lib_dir.exists():
            continue
        for dart in lib_dir.rglob("*.dart"):
            try:
                text = dart.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for lineno, line in enumerate(text.splitlines(), start=1):
                # Neutralise d'abord les interpolations `${...}` (qui peuvent
                # contenir des guillemets, ex. ${map['id']}) pour ne pas tronquer
                # la capture du littéral d'URL.
                line = re.sub(r"\$\{[^{}]*\}", "{param}", line)
                for m in _DART_ENDPOINT_RE.finditer(line):
                    template = _normalize_frontend_path(m.group(1))
                    rel = dart.relative_to(ROOT).as_posix()
                    found.setdefault(template, []).append(
                        {"app": app_name, "file": rel, "line": lineno, "raw": m.group(1)}
                    )
    return found


# ─────────────────────────────────────────────────────────────────────────────
# 3) Croisement
# ─────────────────────────────────────────────────────────────────────────────
def analyze() -> dict:
    backend_routes = collect_backend_routes()
    frontend = collect_frontend_endpoints()

    missing, matched = [], []
    matched_templates: set[str] = set()

    for fe_template, refs in sorted(frontend.items()):
        candidate = _candidate_for_match(fe_template)
        hit = next((r for r in backend_routes if r["match_regex"].match(candidate)), None)
        if hit:
            matched.append({"frontend": fe_template, "backend": hit["template"]})
            matched_templates.add(hit["template"])
        else:
            missing.append({"frontend": fe_template, "refs": refs})

    unused = [
        r["template"]
        for r in backend_routes
        if r["template"] not in matched_templates
    ]
    return {
        "backend_count": len(backend_routes),
        "frontend_count": len(frontend),
        "matched": matched,
        "missing": missing,
        "unused": sorted(unused),
    }


def write_report(result: dict) -> None:
    lines = [
        "# Alignement écrans Flutter ↔ Backend",
        "",
        "> Généré par `qa_e2e/check_screen_backend_alignment.py` "
        "(introspection URLconf Django + scan des littéraux `/api/` des 4 apps).",
        "",
        f"- Routes backend `/api/` : **{result['backend_count']}**",
        f"- Endpoints distincts référencés côté Flutter : **{result['frontend_count']}**",
        f"- Endpoints alignés : **{len(result['matched'])}**",
        f"- ❌ Appels frontend SANS route backend : **{len(result['missing'])}**",
        f"- ℹ️ Routes backend non appelées : **{len(result['unused'])}**",
        "",
    ]
    lines.append("## ❌ Désalignements (à corriger)")
    if not result["missing"]:
        lines.append("\nAucun. Tous les appels frontend ont une route backend. ✅\n")
    else:
        for item in result["missing"]:
            lines.append(f"\n### `{item['frontend']}`")
            for ref in item["refs"]:
                lines.append(f"- `{ref['raw']}` — {ref['app']} · [{ref['file']}:{ref['line']}]({ref['file']}#L{ref['line']})")
    lines.append("\n## ℹ️ Routes backend non référencées par une app")
    if not result["unused"]:
        lines.append("\nAucune.\n")
    else:
        for t in result["unused"]:
            lines.append(f"- `{t}`")
    lines.append("")
    REPORT_PATH.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Sortie JSON brute")
    args = parser.parse_args()

    _bootstrap_django()
    result = analyze()
    write_report(result)

    if args.json:
        # match_regex n'est pas sérialisable : on ne sort que les données.
        print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
    else:
        print(f"Routes backend /api/ : {result['backend_count']}")
        print(f"Endpoints Flutter distincts : {result['frontend_count']}")
        print(f"Alignés : {len(result['matched'])}")
        print(f"MANQUANTS côté backend : {len(result['missing'])}")
        for item in result["missing"]:
            apps = ", ".join(sorted({r["app"] for r in item["refs"]}))
            print(f"  ✗ {item['frontend']}  ({apps})")
        print(f"Routes backend inutilisées : {len(result['unused'])}")
        print(f"\nRapport : {REPORT_PATH.relative_to(ROOT).as_posix()}")

    return 1 if result["missing"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
