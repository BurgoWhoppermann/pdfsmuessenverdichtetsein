"""Main application window."""

import customtkinter as ctk
from tkinter import filedialog, messagebox
from pathlib import Path
from typing import Optional
import threading

try:
    from tkinterdnd2 import TkinterDnD
    DND_AVAILABLE = True
except ImportError:
    DND_AVAILABLE = False

from .drop_zone import DropZone
from .size_slider import SizeSlider
from .options_panel import OptionsPanel
from .page_selector import PageSelectorDialog
from core.pdf_analyzer import PDFAnalyzer
from core.compressor import PDFCompressor
from core.preview_estimator import PreviewEstimator


class MainWindow(ctk.CTk if not DND_AVAILABLE else TkinterDnD.Tk):
    """Main application window."""

    APP_NAME = "PDFs müssen verdichtet sein"

    def __init__(self):
        super().__init__()

        # Apply CustomTkinter styling if using TkinterDnD base
        if DND_AVAILABLE:
            self._apply_ctk_styling()

        self.title(self.APP_NAME)
        self.geometry("400x600")
        self.minsize(350, 550)

        # Set window icon
        self._set_icon()

        # State
        self.current_pdf: Optional[str] = None
        self.is_compressing = False
        self._preview_timer_id: Optional[str] = None
        self._preview_thread: Optional[threading.Thread] = None

        # Create UI
        self._create_widgets()

    def _apply_ctk_styling(self):
        """Apply CustomTkinter styling when using TkinterDnD base."""
        # Set dark mode colors
        self.configure(bg="#1a1a1a")

    def _set_icon(self):
        """Set the window icon."""
        try:
            # Try to find the icon in project root or assets folder
            import sys

            # Get the base path (handles both dev and packaged app)
            if getattr(sys, 'frozen', False):
                base_path = Path(sys._MEIPASS)
            else:
                # Development: go up from src/ui to project root
                base_path = Path(__file__).parent.parent.parent

            # Try image.png in project root first, then assets/icon.png
            icon_paths = [
                base_path / "image.png",
                base_path / "assets" / "icon.png",
            ]

            for icon_path in icon_paths:
                if icon_path.exists():
                    # On macOS, we need to use PIL to set the icon
                    from PIL import Image, ImageTk
                    img = Image.open(icon_path)
                    photo = ImageTk.PhotoImage(img)
                    self.iconphoto(True, photo)
                    # Keep a reference to prevent garbage collection
                    self._icon_photo = photo
                    break
        except Exception:
            pass  # Icon is optional, fail silently

    def _create_widgets(self):
        """Create all UI widgets."""
        # Main container
        self.main_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.main_frame.pack(fill="both", expand=True, padx=20, pady=20)

        # Title
        self.title_label = ctk.CTkLabel(
            self.main_frame,
            text=self.APP_NAME,
            font=ctk.CTkFont(size=20, weight="bold"),
        )
        self.title_label.pack(pady=(0, 20))

        # Drop zone
        self.drop_zone = DropZone(
            self.main_frame,
            on_file_dropped=self._on_file_dropped,
            height=180,
        )
        self.drop_zone.pack(fill="x", pady=(0, 20))

        # Size slider
        self.size_slider = SizeSlider(
            self.main_frame,
            on_value_changed=self._on_slider_changed,
        )
        self.size_slider.pack(fill="x", pady=(0, 20))

        # Options panel
        self.options_panel = OptionsPanel(
            self.main_frame,
            on_page_select_clicked=self._on_page_select,
            on_grayscale_changed=self._on_grayscale_changed,
        )
        self.options_panel.pack(fill="x", pady=(0, 20))

        # Compress button
        self.compress_btn = ctk.CTkButton(
            self.main_frame,
            text="Compress PDF",
            font=ctk.CTkFont(size=15, weight="bold"),
            height=45,
            command=self._on_compress,
            state="disabled",
        )
        self.compress_btn.pack(fill="x", pady=(0, 15))

        # Progress bar
        self.progress_bar = ctk.CTkProgressBar(self.main_frame)
        self.progress_bar.set(0)
        self.progress_bar.pack(fill="x", pady=(0, 5))
        self.progress_bar.pack_forget()  # Hide initially

        # Status label
        self.status_label = ctk.CTkLabel(
            self.main_frame,
            text="",
            font=ctk.CTkFont(size=12),
            text_color=("gray50", "gray60"),
        )
        self.status_label.pack()

        # Result frame (hidden initially)
        self.result_frame = ctk.CTkFrame(self.main_frame, fg_color="transparent")

        self.result_label = ctk.CTkLabel(
            self.result_frame,
            text="",
            font=ctk.CTkFont(size=13),
        )
        self.result_label.pack()

        self.open_btn = ctk.CTkButton(
            self.result_frame,
            text="Open Output Folder",
            width=150,
            command=self._open_output_folder,
        )
        self.open_btn.pack(pady=(10, 0))

    def _on_file_dropped(self, file_path: str):
        """Handle file drop/selection."""
        self.current_pdf = file_path

        # Get file size
        try:
            with PDFAnalyzer(file_path) as analyzer:
                size_mb = analyzer.get_file_size_mb()
                self.size_slider.set_original_size(size_mb)
        except Exception as e:
            messagebox.showerror("Error", f"Could not read PDF: {e}")
            self.drop_zone.reset()
            return

        # Enable compress button
        self.compress_btn.configure(state="normal")

        # Reset results
        self.result_frame.pack_forget()
        self.status_label.configure(text="Ready to compress")

        # Trigger initial preview estimate
        self._schedule_preview_update()

    def _on_slider_changed(self, value: int):
        """Handle slider value change."""
        self._schedule_preview_update()

    def _on_page_select(self):
        """Open page selector dialog."""
        if not self.current_pdf:
            return

        dialog = PageSelectorDialog(
            self,
            self.current_pdf,
            self.options_panel.selected_pages,
        )
        result = dialog.get_result()

        if result is not None:
            self.options_panel.set_selected_pages(result)
            self._schedule_preview_update()

    def _on_grayscale_changed(self, value: bool):
        """Handle grayscale option change."""
        self._schedule_preview_update()

    def _schedule_preview_update(self):
        """Schedule a preview update with debouncing (300ms delay)."""
        if not self.current_pdf:
            return

        # Cancel any pending preview
        if self._preview_timer_id:
            self.after_cancel(self._preview_timer_id)

        # Show loading indicator
        self.size_slider.set_estimate_loading()

        # Schedule new preview after 300ms
        self._preview_timer_id = self.after(300, self._run_preview)

    def _run_preview(self):
        """Run preview estimation in background thread."""
        self._preview_timer_id = None

        if not self.current_pdf or self.is_compressing:
            return

        # Run in background thread to avoid UI freeze
        self._preview_thread = threading.Thread(
            target=self._calculate_preview,
            daemon=True
        )
        self._preview_thread.start()

    def _calculate_preview(self):
        """Calculate preview estimate (runs in background thread)."""
        try:
            estimator = PreviewEstimator(self.current_pdf)
            estimated_size = estimator.estimate_size(
                target_percentage=self.size_slider.get_value(),
                grayscale=self.options_panel.get_grayscale(),
                pages_to_remove=self.options_panel.get_pages_to_remove(),
            )

            # Update UI on main thread
            self.after(0, lambda: self._on_preview_complete(estimated_size))

        except Exception:
            # Silently fail - preview is not critical
            self.after(0, lambda: self.size_slider.clear_estimate())

    def _on_preview_complete(self, estimated_size: int):
        """Handle preview completion (on main thread)."""
        if self.current_pdf:  # Only update if file still loaded
            self.size_slider.set_estimate(estimated_size)

    def _on_compress(self):
        """Start compression."""
        if not self.current_pdf or self.is_compressing:
            return

        # Get output path
        input_path = Path(self.current_pdf)
        default_name = f"{input_path.stem}_compressed.pdf"

        output_path = filedialog.asksaveasfilename(
            title="Save compressed PDF",
            initialdir=input_path.parent,
            initialfile=default_name,
            defaultextension=".pdf",
            filetypes=[("PDF files", "*.pdf")],
        )

        if not output_path:
            return

        self.output_path = output_path
        self.is_compressing = True

        # Update UI
        self.compress_btn.configure(state="disabled")
        self.options_panel.set_enabled(False)
        self.progress_bar.pack(fill="x", pady=(0, 5))
        self.progress_bar.set(0)
        self.result_frame.pack_forget()

        # Run compression in background
        thread = threading.Thread(target=self._run_compression, daemon=True)
        thread.start()

    def _run_compression(self):
        """Run compression in background thread."""
        try:
            compressor = PDFCompressor(
                input_path=self.current_pdf,
                output_path=self.output_path,
                target_percentage=self.size_slider.get_value(),
                grayscale=self.options_panel.get_grayscale(),
                pages_to_remove=self.options_panel.get_pages_to_remove(),
                progress_callback=self._update_progress,
            )

            result = compressor.compress()

            # Update UI on main thread
            self.after(0, lambda: self._on_compression_complete(result))

        except Exception as e:
            self.after(0, lambda: self._on_compression_error(str(e)))

    def _update_progress(self, message: str, percentage: int):
        """Update progress display (called from background thread)."""
        self.after(0, lambda: self._set_progress(message, percentage))

    def _set_progress(self, message: str, percentage: int):
        """Set progress display (on main thread)."""
        self.progress_bar.set(percentage / 100)
        self.status_label.configure(text=message)

    def _on_compression_complete(self, result):
        """Handle compression completion."""
        self.is_compressing = False
        self.compress_btn.configure(state="normal")
        self.options_panel.set_enabled(True)
        self.progress_bar.pack_forget()

        if result.success:
            # Show result
            original_mb = result.original_size / (1024 * 1024)
            final_mb = result.final_size / (1024 * 1024)
            reduction = 100 - result.compression_ratio

            self.result_label.configure(
                text=f"✅ Compressed: {original_mb:.2f} MB → {final_mb:.2f} MB ({reduction:.1f}% reduction)"
            )
            self.result_frame.pack(pady=(10, 0))
            self.status_label.configure(text=result.message)
        else:
            self.status_label.configure(text=f"❌ {result.message}")

    def _on_compression_error(self, error: str):
        """Handle compression error."""
        self.is_compressing = False
        self.compress_btn.configure(state="normal")
        self.options_panel.set_enabled(True)
        self.progress_bar.pack_forget()
        self.status_label.configure(text=f"❌ Error: {error}")

    def _open_output_folder(self):
        """Open the output folder in Finder."""
        import subprocess
        output_path = Path(self.output_path)
        subprocess.run(["open", "-R", str(output_path)])
