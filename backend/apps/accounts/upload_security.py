from __future__ import annotations

import logging
from io import BytesIO
from pathlib import Path
from typing import Iterable

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.files.base import ContentFile

logger = logging.getLogger(__name__)


def _normalized_ext(name: str) -> str:
    return Path(name or "").suffix.lower().strip()


def _max_size_bytes(max_mb: int) -> int:
    return max(1, int(max_mb)) * 1024 * 1024


def _peek_magic_bytes(uploaded_file, length: int = 16) -> bytes:
    """Lit les premiers octets sans consommer le curseur."""
    try:
        if hasattr(uploaded_file, "seek"):
            uploaded_file.seek(0)
        head = uploaded_file.read(length) or b""
    except Exception:
        head = b""
    finally:
        try:
            if hasattr(uploaded_file, "seek"):
                uploaded_file.seek(0)
        except Exception:
            logger.debug("upload_cursor_reset_failed file=%s", getattr(uploaded_file, "name", "?"), exc_info=True)
    if isinstance(head, str):
        head = head.encode("latin-1", errors="ignore")
    return head


_MAGIC_SIGNATURES: dict[str, tuple[bytes, ...]] = {
    ".pdf": (b"%PDF-",),
    ".jpg": (b"\xff\xd8\xff",),
    ".jpeg": (b"\xff\xd8\xff",),
    ".png": (b"\x89PNG\r\n\x1a\n",),
    ".webp": (b"RIFF",),
    ".gif": (b"GIF87a", b"GIF89a"),
    ".docx": (b"PK\x03\x04",),
    ".xlsx": (b"PK\x03\x04",),
    ".pptx": (b"PK\x03\x04",),
    ".odt": (b"PK\x03\x04",),
    ".zip": (b"PK\x03\x04", b"PK\x05\x06"),
    ".mp4": (b"ftyp", b"\x00\x00\x00"),
    ".mp3": (b"ID3", b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"),
    ".mov": (b"ftyp", b"\x00\x00\x00"),
    ".m4v": (b"ftyp", b"\x00\x00\x00"),
    ".webm": (b"\x1a\x45\xdf\xa3",),
    ".m4a": (b"ftyp", b"\x00\x00\x00"),
    ".aac": (b"\xff\xf1", b"\xff\xf9", b"ID3"),
    ".ogg": (b"OggS",),
    ".opus": (b"OggS",),
    ".wav": (b"RIFF",),
}


def _content_matches_extension(ext: str, head: bytes) -> bool:
    expected = _MAGIC_SIGNATURES.get(ext)
    if not expected:
        return False
    if ext == ".webp":
        return head.startswith(b"RIFF") and b"WEBP" in head[:16]
    if ext == ".wav":
        return head.startswith(b"RIFF") and b"WAVE" in head[:16]
    if ext in (".mp4", ".mov", ".m4v", ".m4a"):
        return len(head) >= 8 and head[4:8] == b"ftyp"
    return any(head.startswith(sig) for sig in expected)


def validate_uploaded_file(
    uploaded_file,
    *,
    field_label: str,
    allowed_extensions: Iterable[str],
    max_mb: int,
    allowed_content_types: Iterable[str] | None = None,
) -> None:
    if uploaded_file is None:
        return
    name = getattr(uploaded_file, "name", "") or ""
    ext = _normalized_ext(name)
    normalized_allowed = {str(item).lower().strip() for item in allowed_extensions}
    if normalized_allowed and ext not in normalized_allowed:
        raise ValidationError(
            f"{field_label}: extension invalide ({ext or 'inconnue'}). "
            f"Extensions autorisees: {', '.join(sorted(normalized_allowed))}."
        )

    size = int(getattr(uploaded_file, "size", 0) or 0)
    if size <= 0:
        raise ValidationError(f"{field_label}: fichier vide ou invalide.")
    if size > _max_size_bytes(max_mb):
        raise ValidationError(f"{field_label}: taille maximale depassee ({max_mb} MB).")

    if allowed_content_types:
        content_type = str(getattr(uploaded_file, "content_type", "") or "").lower().strip()
        allowed_types = {str(item).lower().strip() for item in allowed_content_types}
        if not content_type or content_type == "application/octet-stream":
            raise ValidationError(
                f"{field_label}: type MIME requis (Content-Type manquant)."
            )
        if content_type not in allowed_types:
            raise ValidationError(
                f"{field_label}: type MIME non autorise ({content_type})."
            )

    head = _peek_magic_bytes(uploaded_file)
    if head and not _content_matches_extension(ext, head):
        raise ValidationError(
            f"{field_label}: le contenu du fichier ne correspond pas a l'extension {ext}."
        )


def scrub_image_metadata(uploaded_file):
    """
    Best-effort EXIF cleanup for image uploads.
    If Pillow is unavailable or processing fails, the original file is returned.
    """
    if not uploaded_file:
        return uploaded_file
    if not getattr(settings, "UPLOAD_SCRUB_IMAGE_METADATA", True):
        return uploaded_file

    try:
        from PIL import Image
    except ImportError:
        logger.warning("exif_scrub_skipped: Pillow non installe")
        return uploaded_file

    Image.MAX_IMAGE_PIXELS = 25_000_000

    try:
        uploaded_file.seek(0)
        image = Image.open(uploaded_file)
        image_format = (image.format or "PNG").upper()
        if image.mode not in {"RGB", "RGBA", "L"}:
            image = image.convert("RGB")

        clean = Image.new(image.mode, image.size)
        clean.putdata(list(image.getdata()))

        output = BytesIO()
        if image_format in {"JPEG", "JPG"}:
            if clean.mode != "RGB":
                clean = clean.convert("RGB")
            clean.save(output, format="JPEG", quality=90, optimize=True)
        elif image_format == "WEBP":
            clean.save(output, format="WEBP", quality=90)
        else:
            clean.save(output, format="PNG", optimize=True)
        output.seek(0)

        cleaned = ContentFile(output.read())
        cleaned.name = getattr(uploaded_file, "name", "upload_image")
        return cleaned
    except Exception:
        logger.warning(
            "exif_scrub_failed file=%s — fichier original conserve",
            getattr(uploaded_file, "name", "?"), exc_info=True,
        )
        return uploaded_file
