"""PDF compression logic."""

import fitz  # PyMuPDF
import subprocess
import tempfile
import shutil
import io
from pathlib import Path
from typing import Callable, Optional
from dataclasses import dataclass
from PIL import Image


@dataclass
class CompressionResult:
    """Result of a compression operation."""
    success: bool
    output_path: Optional[Path]
    original_size: int
    final_size: int
    compression_ratio: float
    message: str


# DPI thresholds based on target compression percentage
DPI_THRESHOLDS = [
    (80, 150),   # 80-100% target: use 150 DPI
    (50, 120),   # 50-80% target: use 120 DPI
    (30, 100),   # 30-50% target: use 100 DPI
    (10, 72),    # 10-30% target: use 72 DPI
    (0, 50),     # <10% target: use 50 DPI (fallback)
]


class PDFCompressor:
    """Compresses PDF files with various options."""

    def __init__(
        self,
        input_path: str,
        output_path: str,
        target_percentage: int = 50,
        grayscale: bool = False,
        pages_to_remove: Optional[set[int]] = None,
        progress_callback: Optional[Callable[[str, int], None]] = None,
    ):
        self.input_path = Path(input_path)
        self.output_path = Path(output_path)
        self.target_percentage = target_percentage
        self.grayscale = grayscale
        self.pages_to_remove = pages_to_remove or set()
        self.progress_callback = progress_callback or (lambda m, p: None)

    def _report_progress(self, message: str, percentage: int):
        self.progress_callback(message, percentage)

    def compress(self) -> CompressionResult:
        """Execute compression with all configured options."""
        original_size = self.input_path.stat().st_size
        target_size = int(original_size * (self.target_percentage / 100))

        self._report_progress("Opening PDF...", 5)

        try:
            # Prepare document (remove pages if needed)
            temp_input = self._prepare_document()
            input_for_compression = temp_input or self.input_path

            # Try image-based compression with binary search
            self._report_progress("Compressing images...", 10)
            result_path = self._compress_with_binary_search(
                input_for_compression, target_size
            )

            if result_path and result_path.stat().st_size <= target_size:
                shutil.move(str(result_path), str(self.output_path))
                self._cleanup(temp_input, None)
                return self._make_result(original_size, "Compression successful")

            # Try Ghostscript if available
            self._report_progress("Trying Ghostscript...", 60)
            gs_result = self._compress_with_ghostscript(input_for_compression, target_size)

            if gs_result:
                # Compare results and use the smaller one
                gs_size = self.output_path.stat().st_size
                jpeg_size = result_path.stat().st_size if result_path else float('inf')

                if jpeg_size < gs_size and result_path:
                    shutil.move(str(result_path), str(self.output_path))
                elif result_path:
                    result_path.unlink()

                self._cleanup(temp_input, None)
                return self._make_result(original_size, "Compression successful")

            # Use best JPEG result if GS failed
            if result_path:
                shutil.move(str(result_path), str(self.output_path))
                self._cleanup(temp_input, None)
                return self._make_result(original_size, "Compression successful")

            # Last resort: basic save with cleanup
            self._report_progress("Applying basic optimization...", 90)
            with fitz.open(input_for_compression) as doc:
                doc.save(
                    str(self.output_path),
                    garbage=4,
                    deflate=True,
                    clean=True,
                )

            self._cleanup(temp_input, None)
            return self._make_result(original_size, "Basic optimization applied")

        except Exception as e:
            return CompressionResult(
                success=False,
                output_path=None,
                original_size=original_size,
                final_size=0,
                compression_ratio=0,
                message=f"Compression failed: {str(e)}"
            )

    def _prepare_document(self) -> Optional[Path]:
        """Remove pages if needed and return temp path, or None."""
        if not self.pages_to_remove:
            return None

        temp_path = Path(tempfile.mktemp(suffix=".pdf"))
        with fitz.open(self.input_path) as doc:
            for page_num in sorted(self.pages_to_remove, reverse=True):
                if 0 <= page_num < len(doc):
                    doc.delete_page(page_num)
            doc.save(str(temp_path))
        return temp_path

    def _select_dpi_for_target(self) -> int:
        """Select appropriate DPI based on target percentage."""
        for threshold, dpi in DPI_THRESHOLDS:
            if self.target_percentage >= threshold:
                return dpi
        return 50  # Fallback to lowest DPI

    def _compress_with_binary_search(
        self, input_path: Path, target_size: int
    ) -> Optional[Path]:
        """Use binary search to find optimal JPEG quality for target size."""
        dpi = self._select_dpi_for_target()
        best_path: Optional[Path] = None
        best_size = 0  # Track size closest to target (without exceeding)
        best_quality = None
        iterations = 0
        max_iterations = 10  # Binary search on 1-100 needs at most ~7 iterations

        low, high = 5, 95

        self._report_progress(f"Using DPI={dpi}, searching for optimal quality...", 15)

        while low <= high and iterations < max_iterations:
            iterations += 1
            mid = (low + high) // 2
            progress = 15 + int((iterations / max_iterations) * 40)
            self._report_progress(f"Trying quality={mid}%...", progress)

            try:
                temp_path = Path(tempfile.mktemp(suffix=".pdf"))
                self._render_pdf_as_jpeg(input_path, temp_path, dpi, mid)
                current_size = temp_path.stat().st_size

                # Check if within tolerance (±5% of target)
                tolerance_ratio = abs(current_size - target_size) / target_size
                if tolerance_ratio < 0.05:
                    # Close enough - use this result
                    if best_path and best_path.exists():
                        best_path.unlink()
                    return temp_path

                if current_size <= target_size:
                    # Under target - this is a valid result
                    # Track if it's closer to target than previous best
                    if current_size > best_size:
                        if best_path and best_path.exists():
                            best_path.unlink()
                        best_path = temp_path
                        best_size = current_size
                        best_quality = mid
                    else:
                        temp_path.unlink()
                    low = mid + 1  # Try higher quality
                else:
                    # Over target - need more compression
                    temp_path.unlink()
                    high = mid - 1

            except Exception:
                high = mid - 1
                continue

        # If no result found with current DPI, try lower DPI
        if best_path is None and dpi > 50:
            return self._compress_with_lower_dpi(input_path, target_size, dpi)

        return best_path

    def _compress_with_lower_dpi(
        self, input_path: Path, target_size: int, current_dpi: int
    ) -> Optional[Path]:
        """Fallback: try lower DPI values if current DPI can't hit target."""
        fallback_dpis = [d for _, d in DPI_THRESHOLDS if d < current_dpi]

        for dpi in fallback_dpis:
            self._report_progress(f"Trying lower DPI={dpi}...", 55)

            # Quick binary search at lower DPI
            low, high = 5, 95
            best_path = None
            best_size = 0

            while low <= high:
                mid = (low + high) // 2
                try:
                    temp_path = Path(tempfile.mktemp(suffix=".pdf"))
                    self._render_pdf_as_jpeg(input_path, temp_path, dpi, mid)
                    current_size = temp_path.stat().st_size

                    if current_size <= target_size:
                        if current_size > best_size:
                            if best_path and best_path.exists():
                                best_path.unlink()
                            best_path = temp_path
                            best_size = current_size
                        else:
                            temp_path.unlink()
                        low = mid + 1
                    else:
                        temp_path.unlink()
                        high = mid - 1
                except Exception:
                    high = mid - 1
                    continue

            if best_path:
                return best_path

        return None

    def _render_pdf_as_jpeg(
        self, input_path: Path, output_path: Path, dpi: int, quality: int
    ):
        """Render each page as JPEG and create new PDF."""
        with fitz.open(input_path) as src_doc:
            new_doc = fitz.open()

            for page_num in range(len(src_doc)):
                page = src_doc[page_num]

                # Render at target DPI
                zoom = dpi / 72.0
                mat = fitz.Matrix(zoom, zoom)

                if self.grayscale:
                    pix = page.get_pixmap(matrix=mat, alpha=False, colorspace=fitz.csGRAY)
                else:
                    pix = page.get_pixmap(matrix=mat, alpha=False)

                # Convert to JPEG using PIL for better compression control
                img = Image.frombytes("RGB" if not self.grayscale else "L",
                                      [pix.width, pix.height], pix.samples)

                jpeg_buffer = io.BytesIO()
                img.save(jpeg_buffer, format="JPEG", quality=quality, optimize=True)
                jpeg_data = jpeg_buffer.getvalue()

                # Create new page with original dimensions
                new_page = new_doc.new_page(
                    width=page.rect.width,
                    height=page.rect.height
                )

                # Insert JPEG image
                new_page.insert_image(
                    new_page.rect,
                    stream=jpeg_data,
                )

            # Save with maximum compression
            new_doc.save(
                str(output_path),
                garbage=4,
                deflate=True,
                clean=True,
            )
            new_doc.close()

    def _compress_with_ghostscript(self, input_path: Path, target_size: int) -> bool:
        """Use Ghostscript for aggressive compression."""
        gs_cmd = shutil.which("gs")
        if not gs_cmd:
            return False

        # More aggressive Ghostscript settings
        gs_configs = [
            # (setting, image_dpi, color_image_quality)
            ("/ebook", 150, 75),
            ("/ebook", 100, 60),
            ("/screen", 72, 50),
            ("/screen", 50, 30),
        ]

        # Find starting point based on target
        start_idx = 0
        if self.target_percentage < 30:
            start_idx = 2
        elif self.target_percentage < 50:
            start_idx = 1

        for i, (setting, img_dpi, img_quality) in enumerate(gs_configs[start_idx:]):
            progress = 60 + int((i / len(gs_configs)) * 30)
            self._report_progress(f"Ghostscript {setting} @ {img_dpi}dpi...", progress)

            cmd = [
                gs_cmd,
                "-sDEVICE=pdfwrite",
                "-dCompatibilityLevel=1.4",
                f"-dPDFSETTINGS={setting}",
                "-dNOPAUSE",
                "-dQUIET",
                "-dBATCH",
                # Image downsampling
                "-dDownsampleColorImages=true",
                "-dDownsampleGrayImages=true",
                "-dDownsampleMonoImages=true",
                f"-dColorImageResolution={img_dpi}",
                f"-dGrayImageResolution={img_dpi}",
                f"-dMonoImageResolution={img_dpi}",
                # JPEG compression for images
                "-dAutoFilterColorImages=false",
                "-dAutoFilterGrayImages=false",
                "-dColorImageFilter=/DCTEncode",
                "-dGrayImageFilter=/DCTEncode",
                f"-dJPEGQ={img_quality}",
                # Remove metadata
                "-dFastWebView=false",
            ]

            if self.grayscale:
                cmd.extend([
                    "-sColorConversionStrategy=Gray",
                    "-dProcessColorModel=/DeviceGray",
                ])

            cmd.extend([
                f"-sOutputFile={self.output_path}",
                str(input_path),
            ])

            try:
                result = subprocess.run(cmd, capture_output=True, timeout=120)

                if result.returncode == 0 and self.output_path.exists():
                    if self.output_path.stat().st_size <= target_size:
                        return True
            except subprocess.TimeoutExpired:
                continue
            except Exception:
                continue

        return self.output_path.exists()

    def _make_result(self, original_size: int, message: str) -> CompressionResult:
        """Create a success result."""
        final_size = self.output_path.stat().st_size
        self._report_progress("Done!", 100)
        return CompressionResult(
            success=True,
            output_path=self.output_path,
            original_size=original_size,
            final_size=final_size,
            compression_ratio=final_size / original_size * 100,
            message=message
        )

    def _cleanup(self, *paths):
        """Clean up temporary files."""
        for path in paths:
            if path and path.exists():
                try:
                    path.unlink()
                except Exception:
                    pass
