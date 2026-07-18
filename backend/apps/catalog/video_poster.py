"""Extraction d'un poster (vignette) depuis une video produit.

Utilise le binaire ffmpeg embarque par `imageio-ffmpeg` : aucun ffmpeg
systeme requis, le wheel manylinux embarque un binaire statique. Toute la
chaine est defensive — si ffmpeg est indisponible ou echoue, on renvoie
`None` et la publication continue sans poster (degradation gracieuse).
"""

import logging
import os
import subprocess
import tempfile

from django.core.files.base import ContentFile

logger = logging.getLogger(__name__)

# Largeur max du poster ; hauteur auto (paire pour les codecs).
_POSTER_MAX_WIDTH = 720
# Au-dela, on considere l'extraction figee (clip protege/corrompu).
_FFMPEG_TIMEOUT_SECONDS = 60


def _ffmpeg_exe():
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:  # pragma: no cover - dependance absente
        logger.warning("imageio-ffmpeg indisponible : poster video ignore.")
        return None


def _run_ffmpeg(cmd):
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=_FFMPEG_TIMEOUT_SECONDS,
        )
        return result.returncode == 0
    except (subprocess.SubprocessError, OSError):
        return False


def generate_video_poster(video_fieldfile, *, at_seconds: float = 1.0):
    """Renvoie un `ContentFile` JPEG (1 frame) ou `None` en cas d'echec.

    `video_fieldfile` est un `FieldFile` Django (ex. `product.video`). Le
    contenu est streame vers un fichier temporaire local pour rester agnostique
    du backend de stockage (S3/local).
    """
    ffmpeg_exe = _ffmpeg_exe()
    if ffmpeg_exe is None or not video_fieldfile:
        return None

    tmp_in = None
    tmp_out = None
    try:
        suffix = os.path.splitext(getattr(video_fieldfile, "name", "") or "")[1] or ".mp4"
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as fin:
            video_fieldfile.open("rb")
            try:
                for chunk in video_fieldfile.chunks():
                    fin.write(chunk)
            finally:
                video_fieldfile.close()
            tmp_in = fin.name

        fd, tmp_out = tempfile.mkstemp(suffix=".jpg")
        os.close(fd)

        scale = f"scale='min({_POSTER_MAX_WIDTH},iw)':-2"
        # Seek rapide a `at_seconds` (avant -i) puis 1 frame.
        primary = [
            ffmpeg_exe, "-y", "-ss", str(at_seconds), "-i", tmp_in,
            "-frames:v", "1", "-q:v", "3", "-vf", scale, tmp_out,
        ]
        ok = _run_ffmpeg(primary)
        if not ok or not os.path.exists(tmp_out) or os.path.getsize(tmp_out) == 0:
            # Clip plus court que `at_seconds` : on prend la toute premiere frame.
            fallback = [
                ffmpeg_exe, "-y", "-i", tmp_in,
                "-frames:v", "1", "-q:v", "3", "-vf", scale, tmp_out,
            ]
            _run_ffmpeg(fallback)

        if os.path.exists(tmp_out) and os.path.getsize(tmp_out) > 0:
            with open(tmp_out, "rb") as fout:
                return ContentFile(fout.read())
        return None
    except Exception:  # noqa: BLE001 - jamais bloquer la publication
        logger.exception("Echec generation poster video.")
        return None
    finally:
        for path in (tmp_in, tmp_out):
            if path and os.path.exists(path):
                try:
                    os.remove(path)
                except OSError:
                    pass
