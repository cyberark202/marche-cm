from __future__ import annotations

from io import BytesIO
from pathlib import Path
from typing import Iterable

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.files.base import ContentFile


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
            pass
    if isinstance(head, str):
        try:
            head = head.encode("latin-1", errors="ignore")
        except Exception:
            head = b""
    return head


_MAGIC_SIGNATURES: dict[str, tuple[bytes, ...]] = {
    ".pdf": (b"%PDF-",),
    ".jpg": (b"\xff\xd8\xff",),
    ".jpeg": (b"\xff\xd8\xff",),
    ".png": (b"\x89PNG\r\n\x1a\n",),
    ".webp": (b"RIFF",),
    ".gif": (b"GIF87a", b"GIF89a"),
}


def _content_matches_extension(ext: str, head: bytes) -> bool:
    expected = _MAGIC_SIGNATURES.get(ext)
    if not expected:
        # Extension non couverte par notre table: on ne bloque pas (sera filtree
        # par allowed_extensions en amont). Mieux vaut ne pas casser un cas
        # legitime imprevu (ex: .docx) que d'etre faussement strict.
        return True
    if ext == ".webp":
        return head.startswith(b"RIFF") and b"WEBP" in head[:16]
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
        if content_type and content_type not in allowed_types:
            raise ValidationError(
                f"{field_label}: type MIME non autorise ({content_type})."
            )

    # Defense en profondeur: verifier les magic bytes du fichier pour empecher
    # un attaquant de renommer un .exe en .pdf ou d'uploader du HTML/JS dans un
    # champ image. La whitelist d'extensions ci-dessus n'est pas suffisante.
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
    except Exception:
        return uploaded_file

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
        return uploaded_file
