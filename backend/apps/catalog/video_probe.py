"""Validation de profondeur pour les videos uploadees.

La validation magic-bytes (`upload_security.validate_uploaded_file`) confirme
seulement qu'un fichier *commence* comme un conteneur MP4/MOV/WebM. Elle laisse
passer des fichiers « coquilles vides » : un `ftyp` valide suivi d'un `mdat`
rempli de zeros, sans piste video ni frame decodable. Ces fichiers sont
acceptes, stockes, servis... puis echouent a l'initialisation cote lecteur
(web/mobile) — exactement le symptome « la video ne se lit pas ».

Ce module verifie qu'une video contient reellement une piste video lisible :

1. Probe ffmpeg (binaire embarque par `imageio-ffmpeg`, deja utilise pour le
   poster) : on confirme >= 1 flux video et une duree > 0. C'est la verification
   autoritaire.
2. Repli structurel ISO-BMFF si ffmpeg est indisponible : on exige la presence
   d'une box `moov` (metadonnees de piste) et on rejette le `mdat` tout-a-zero.

Toute la chaine est defensive : une panne ffmpeg transitoire ne doit pas bloquer
un upload legitime (on retombe sur le check structurel), mais un contenu
prouve invalide est rejete via `ValidationError`.
"""

from __future__ import annotations

import logging
import os
import re
import subprocess
import tempfile

from django.core.exceptions import ValidationError

logger = logging.getLogger(__name__)

_PROBE_TIMEOUT_SECONDS = 30
# Au-dela, le conteneur est probablement tronque/corrompu : un vrai clip pese
# bien plus que quelques Ko (le dummy QA faisait 2088 octets).
_MIN_PLAUSIBLE_BYTES = 8 * 1024

_DURATION_RE = re.compile(r"Duration:\s*(\d+):(\d{2}):(\d{2})(?:\.(\d+))?")


def _ffmpeg_exe():
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:  # pragma: no cover - dependance absente
        logger.warning("imageio-ffmpeg indisponible : probe video structurel uniquement.")
        return None


def _spool_to_temp(uploaded_file) -> str:
    """Ecrit l'upload dans un fichier temporaire local et renvoie son chemin."""
    suffix = os.path.splitext(getattr(uploaded_file, "name", "") or "")[1] or ".mp4"
    fd, path = tempfile.mkstemp(suffix=suffix)
    try:
        with os.fdopen(fd, "wb") as out:
            uploaded_file.seek(0)
            for chunk in uploaded_file.chunks():
                out.write(chunk)
    finally:
        try:
            uploaded_file.seek(0)
        except Exception:
            logger.debug("video_spool_cursor_reset_failed file=%s", getattr(uploaded_file, "name", "?"), exc_info=True)
    return path


def _ffmpeg_probe(path: str) -> tuple[bool, float] | None:
    """Renvoie (a_un_flux_video, duree_sec) via ffmpeg, ou None si indisponible/echec.

    Astuce : `ffmpeg -i <fichier>` sans sortie quitte en erreur mais imprime les
    infos de flux sur stderr (« Stream ... Video: », « Duration: HH:MM:SS.ss »).
    """
    ffmpeg = _ffmpeg_exe()
    if not ffmpeg:
        return None
    try:
        proc = subprocess.run(
            [ffmpeg, "-hide_banner", "-i", path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=_PROBE_TIMEOUT_SECONDS,
        )
    except (subprocess.SubprocessError, OSError):
        return None
    stderr = (proc.stderr or b"").decode("utf-8", errors="ignore")
    has_video = bool(re.search(r"Stream #\d+:\d+.*: Video:", stderr))
    duration = 0.0
    match = _DURATION_RE.search(stderr)
    if match:
        hours, minutes, seconds, frac = match.groups()
        duration = int(hours) * 3600 + int(minutes) * 60 + int(seconds)
        if frac:
            duration += float(f"0.{frac}")
    return has_video, duration


def _iso_bmff_has_video_moov(path: str) -> bool:
    """Check structurel ISO-BMFF : la box `moov` existe et n'est pas vide.

    Parcourt les box de premier niveau. Le fichier dummy QA (ftyp + mdat
    tout-a-zero, pas de moov) est rejete ; un vrai mp4/mov a toujours un moov.
    """
    try:
        size = os.path.getsize(path)
        if size < _MIN_PLAUSIBLE_BYTES:
            return False
        with open(path, "rb") as fp:
            offset = 0
            while offset < size:
                fp.seek(offset)
                header = fp.read(8)
                if len(header) < 8:
                    break
                box_size = int.from_bytes(header[0:4], "big")
                box_type = header[4:8]
                if box_size == 1:  # 64-bit extended size
                    ext = fp.read(8)
                    if len(ext) < 8:
                        break
                    box_size = int.from_bytes(ext, "big")
                if box_type == b"moov" and box_size > 8:
                    return True
                if box_size <= 0:  # box s'etend jusqu'a EOF : pas de moov apres
                    break
                offset += box_size
    except OSError:
        return True  # I/O douteux : ne pas bloquer sur le repli
    return False


def validate_video_stream(uploaded_file, *, field_label: str = "Video produit") -> float:
    """Valide qu'un upload contient une piste video lisible. Renvoie la duree (sec).

    Leve `ValidationError` si le fichier est prouve sans flux video / sans duree.
    Best-effort : si ffmpeg est absent, on retombe sur un check structurel ; si
    ffmpeg plante (timeout/crash), on ne bloque pas un upload potentiellement
    valide.
    """
    if uploaded_file is None:
        return 0.0

    if int(getattr(uploaded_file, "size", 0) or 0) < _MIN_PLAUSIBLE_BYTES:
        raise ValidationError(
            f"{field_label}: fichier video trop petit ou vide (aucune piste video)."
        )

    path = None
    try:
        path = _spool_to_temp(uploaded_file)
        probe = _ffmpeg_probe(path)
        if probe is not None:
            has_video, duration = probe
            if not has_video:
                raise ValidationError(
                    f"{field_label}: aucun flux video decodable dans le fichier."
                )
            if duration <= 0:
                raise ValidationError(
                    f"{field_label}: video de duree nulle ou illisible."
                )
            return duration
        # ffmpeg indisponible -> repli structurel.
        ext = os.path.splitext(getattr(uploaded_file, "name", "") or "")[1].lower()
        if ext in {".mp4", ".mov", ".m4v"} and not _iso_bmff_has_video_moov(path):
            raise ValidationError(
                f"{field_label}: conteneur video invalide (metadonnees de piste absentes)."
            )
        return 0.0
    finally:
        if path and os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass
