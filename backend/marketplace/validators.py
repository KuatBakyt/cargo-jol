from pathlib import Path

from django.core.exceptions import ValidationError
from PIL import Image


def validate_attachment(file):
    """Allow small image/PDF uploads, verify bytes rather than client MIME headers."""
    if file.size > 10 * 1024 * 1024:
        raise ValidationError("Maximum file size is 10 MB.")
    suffix = Path(file.name).suffix.lower()
    try:
        if suffix in {".jpg", ".jpeg", ".png"}:
            with Image.open(file) as image:
                if image.format not in {"JPEG", "PNG"}:
                    raise ValidationError("Unsupported image format.")
                image.verify()
        elif suffix == ".pdf":
            if file.read(5) != b"%PDF-":
                raise ValidationError("Invalid PDF header.")
        else:
            raise ValidationError("Only JPEG, PNG and PDF files are supported.")
    except (OSError, Image.DecompressionBombError) as exc:
        raise ValidationError("Invalid image.") from exc
    finally:
        file.seek(0)
