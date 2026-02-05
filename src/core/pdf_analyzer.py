"""PDF analysis utilities."""

import fitz  # PyMuPDF
from pathlib import Path
from typing import Optional
from PIL import Image
import io


class PDFAnalyzer:
    """Analyzes PDF files for size, page count, and generates thumbnails."""

    def __init__(self, pdf_path: str):
        self.pdf_path = Path(pdf_path)
        self._doc: Optional[fitz.Document] = None

    def __enter__(self):
        self._doc = fitz.open(self.pdf_path)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self._doc:
            self._doc.close()

    @property
    def doc(self) -> fitz.Document:
        if self._doc is None:
            raise RuntimeError("PDFAnalyzer must be used as context manager")
        return self._doc

    def get_file_size(self) -> int:
        """Get file size in bytes."""
        return self.pdf_path.stat().st_size

    def get_file_size_mb(self) -> float:
        """Get file size in megabytes."""
        return self.get_file_size() / (1024 * 1024)

    def get_page_count(self) -> int:
        """Get total number of pages."""
        return len(self.doc)

    def get_page_thumbnail(self, page_num: int, max_size: int = 150) -> Image.Image:
        """Generate a thumbnail for a specific page.

        Args:
            page_num: Zero-indexed page number
            max_size: Maximum dimension (width or height) of thumbnail

        Returns:
            PIL Image of the page thumbnail
        """
        page = self.doc[page_num]

        # Calculate zoom to fit within max_size
        rect = page.rect
        zoom = max_size / max(rect.width, rect.height)
        matrix = fitz.Matrix(zoom, zoom)

        # Render page to pixmap
        pixmap = page.get_pixmap(matrix=matrix, alpha=False)

        # Convert to PIL Image
        img_data = pixmap.tobytes("png")
        img = Image.open(io.BytesIO(img_data))

        return img

    def get_all_thumbnails(self, max_size: int = 150) -> list[Image.Image]:
        """Generate thumbnails for all pages."""
        return [self.get_page_thumbnail(i, max_size) for i in range(len(self.doc))]
