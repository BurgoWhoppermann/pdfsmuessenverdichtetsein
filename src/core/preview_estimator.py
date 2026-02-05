"""Preview size estimation for PDF compression."""

import fitz  # PyMuPDF
import io
from pathlib import Path
from typing import Optional
from PIL import Image


# DPI settings based on target percentage (same as compressor.py)
DPI_THRESHOLDS = [
    (80, 150),
    (50, 120),
    (30, 100),
    (10, 72),
    (0, 50),
]


class PreviewEstimator:
    """Estimates compressed file size by sampling a single page."""

    def __init__(self, pdf_path: str):
        self.pdf_path = Path(pdf_path)

    def estimate_size(
        self,
        target_percentage: int,
        grayscale: bool = False,
        pages_to_remove: Optional[set[int]] = None,
    ) -> int:
        """Estimate compressed file size based on sample page compression.

        Args:
            target_percentage: Target size as percentage of original (10-100)
            grayscale: Whether to convert to grayscale
            pages_to_remove: Set of zero-indexed page numbers to exclude

        Returns:
            Estimated final size in bytes
        """
        pages_to_remove = pages_to_remove or set()

        with fitz.open(self.pdf_path) as doc:
            total_pages = len(doc)
            remaining_pages = total_pages - len(pages_to_remove)

            if remaining_pages <= 0:
                return 0

            # Find first non-removed page to use as sample
            sample_page_num = 0
            for i in range(total_pages):
                if i not in pages_to_remove:
                    sample_page_num = i
                    break

            # Compress sample page
            sample_size = self._compress_sample_page(
                doc, sample_page_num, target_percentage, grayscale
            )

            # Extrapolate to full document
            # Add small overhead for PDF structure (~2KB per page + 10KB base)
            pdf_overhead = 10_000 + (remaining_pages * 2_000)
            estimated_size = (sample_size * remaining_pages) + pdf_overhead

            return int(estimated_size)

    def _select_dpi(self, target_percentage: int) -> int:
        """Select appropriate DPI based on target percentage."""
        for threshold, dpi in DPI_THRESHOLDS:
            if target_percentage >= threshold:
                return dpi
        return 50

    def _select_quality(self, target_percentage: int) -> int:
        """Estimate JPEG quality based on target percentage."""
        # Map target percentage to quality range
        # Higher target % -> higher quality
        if target_percentage >= 80:
            return 85
        elif target_percentage >= 60:
            return 70
        elif target_percentage >= 40:
            return 55
        elif target_percentage >= 25:
            return 40
        else:
            return 25

    def _compress_sample_page(
        self,
        doc: fitz.Document,
        page_num: int,
        target_percentage: int,
        grayscale: bool,
    ) -> int:
        """Compress a single page and return its size in bytes.

        Args:
            doc: Open fitz document
            page_num: Page number to compress
            target_percentage: Target compression percentage
            grayscale: Whether to convert to grayscale

        Returns:
            Size of compressed page in bytes
        """
        dpi = self._select_dpi(target_percentage)
        quality = self._select_quality(target_percentage)

        page = doc[page_num]

        # Render at target DPI
        zoom = dpi / 72.0
        mat = fitz.Matrix(zoom, zoom)

        if grayscale:
            pix = page.get_pixmap(matrix=mat, alpha=False, colorspace=fitz.csGRAY)
            img = Image.frombytes("L", [pix.width, pix.height], pix.samples)
        else:
            pix = page.get_pixmap(matrix=mat, alpha=False)
            img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)

        # Compress to JPEG
        jpeg_buffer = io.BytesIO()
        img.save(jpeg_buffer, format="JPEG", quality=quality, optimize=True)
        jpeg_size = len(jpeg_buffer.getvalue())

        return jpeg_size
