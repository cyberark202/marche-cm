from io import BytesIO
from pathlib import Path

from django.core.files.base import ContentFile


def _is_image_extension(ext: str) -> bool:
    return ext in {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"}


def generate_compliance_preview(document) -> bool:
    """
    Create a preview image from the first page of a compliance document.
    - Images: reuse source image.
    - PDFs: render first page to JPEG (requires pypdfium2 at runtime).
    """
    if document is None or not document.file:
        return False
    ext = Path(document.file.name).suffix.lower()

    if _is_image_extension(ext):
        if document.preview_image != document.file:
            document.preview_image = document.file
            document.save(update_fields=["preview_image"])
        return True

    if ext != ".pdf":
        return False

    try:
        import pypdfium2 as pdfium
    except Exception:
        return False

    try:
        with document.file.open("rb") as fh:
            pdf_bytes = fh.read()
        pdf = pdfium.PdfDocument(pdf_bytes)
        if len(pdf) < 1:
            return False
        page = pdf[0]
        rendered = page.render(scale=1.5)
        pil_image = rendered.to_pil()
        page.close()
        pdf.close()

        stream = BytesIO()
        pil_image.save(stream, format="JPEG", quality=85)
        stream.seek(0)
        preview_name = f"{Path(document.file.name).stem}_page1.jpg"
        document.preview_image.save(preview_name, ContentFile(stream.read()), save=True)
        return True
    except Exception:
        return False
