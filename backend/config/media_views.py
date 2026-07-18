"""Service des fichiers media avec support des requetes HTTP Range (206).

Le serveur de developpement Django/Channels sert `/media/` via
`django.views.static.serve`, qui **ignore le header `Range`** : il repond
toujours `200 OK` avec le fichier complet, sans `Accept-Ranges`. Or les
elements `<video>` HTML5 (donc Flutter web) ont besoin de `206 Partial
Content` pour lire un MP4 dont l'atome `moov` est en fin de fichier (clips non
« faststart ») : sans Range, le navigateur ne peut pas recuperer les
metadonnees de piste et la lecture echoue.

Cette vue n'est branchee qu'en DEBUG (en prod, les media sont servis par S3 /
CloudFront, qui gerent nativement le Range). Elle inclut une protection contre
le path traversal et reste volontairement minimale.
"""

from __future__ import annotations

import mimetypes
import os
import re

from django.conf import settings
from django.http import (
    FileResponse,
    Http404,
    HttpResponse,
    HttpResponseNotModified,
    StreamingHttpResponse,
)
from django.utils.http import http_date
from django.views.static import was_modified_since

_RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)", re.IGNORECASE)
_CHUNK = 8192


def _safe_full_path(relative_path: str) -> str:
    media_root = os.path.abspath(settings.MEDIA_ROOT)
    full_path = os.path.abspath(os.path.join(media_root, relative_path))
    # Protection path traversal : le chemin resolu doit rester sous MEDIA_ROOT.
    if os.path.commonpath([media_root, full_path]) != media_root:
        raise Http404("Chemin media invalide.")
    if not os.path.isfile(full_path):
        raise Http404("Fichier media introuvable.")
    return full_path


def serve_media_with_range(request, path: str):
    full_path = _safe_full_path(path)
    statobj = os.stat(full_path)

    # Respecte If-Modified-Since (304) comme django.views.static.serve.
    if not was_modified_since(
        request.META.get("HTTP_IF_MODIFIED_SINCE"), statobj.st_mtime
    ):
        return _allow_cross_origin(HttpResponseNotModified())

    content_type = mimetypes.guess_type(full_path)[0] or "application/octet-stream"
    file_size = statobj.st_size
    range_header = request.META.get("HTTP_RANGE", "").strip()
    match = _RANGE_RE.match(range_header) if range_header else None

    if match:
        start_str, end_str = match.groups()
        start = int(start_str) if start_str else 0
        end = int(end_str) if end_str else file_size - 1
        end = min(end, file_size - 1)
        if start > end or start >= file_size:
            resp = HttpResponse(status=416)  # Range Not Satisfiable
            resp["Content-Range"] = f"bytes */{file_size}"
            return _allow_cross_origin(resp)

        length = end - start + 1
        fh = open(full_path, "rb")
        fh.seek(start)
        resp = StreamingHttpResponse(
            _iter_range(fh, length),
            status=206,
            content_type=content_type,
        )
        resp["Content-Length"] = str(length)
        resp["Content-Range"] = f"bytes {start}-{end}/{file_size}"
    else:
        resp = FileResponse(open(full_path, "rb"), content_type=content_type)
        resp["Content-Length"] = str(file_size)

    resp["Accept-Ranges"] = "bytes"
    resp["Last-Modified"] = http_date(statobj.st_mtime)
    return _allow_cross_origin(resp)


def _allow_cross_origin(resp):
    """Autorise l'embarquement cross-origin du media (QA web).

    En QA, l'app Flutter web est servie sur `localhost:<port>` mais les URLs
    media sont absolues sur `127.0.0.1:8000` (hote different pour le navigateur).
    Sans ces en-tetes, Chrome bloque la requete `<video>` no-cors via ORB
    (`ERR_BLOCKED_BY_RESPONSE.NotSameOrigin`) -> « Format error ». On opte donc
    explicitement le media dans l'embarquement cross-origin. Inoffensif : vue
    DEBUG-only ; en prod c'est S3/CloudFront qui gere ces en-tetes.
    """
    resp["Access-Control-Allow-Origin"] = "*"
    resp["Cross-Origin-Resource-Policy"] = "cross-origin"
    return resp


def _iter_range(fh, length: int):
    try:
        remaining = length
        while remaining > 0:
            chunk = fh.read(min(_CHUNK, remaining))
            if not chunk:
                break
            remaining -= len(chunk)
            yield chunk
    finally:
        fh.close()
