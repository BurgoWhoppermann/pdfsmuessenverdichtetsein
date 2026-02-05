"""Page selector dialog with thumbnail grid."""

import customtkinter as ctk
from typing import Optional
from PIL import Image, ImageTk
import threading

from core.pdf_analyzer import PDFAnalyzer


class PageThumbnail(ctk.CTkFrame):
    """A clickable page thumbnail."""

    def __init__(
        self,
        master,
        page_num: int,
        image: Optional[Image.Image] = None,
        selected: bool = False,
        on_click=None,
        **kwargs
    ):
        super().__init__(master, **kwargs)

        self.page_num = page_num
        self.selected = selected
        self.on_click = on_click
        self._photo_image = None

        self.configure(
            fg_color=("gray85", "gray20") if not selected else ("#3b8ed0", "#1f6aa5"),
            corner_radius=8,
        )

        # Image label
        self.image_label = ctk.CTkLabel(
            self,
            text="",
            width=120,
            height=160,
        )
        self.image_label.pack(padx=5, pady=(5, 2))

        if image:
            self.set_image(image)

        # Page number label
        self.page_label = ctk.CTkLabel(
            self,
            text=f"Page {page_num + 1}",
            font=ctk.CTkFont(size=11),
        )
        self.page_label.pack(pady=(0, 5))

        # Bind click events
        self.bind("<Button-1>", self._handle_click)
        self.image_label.bind("<Button-1>", self._handle_click)
        self.page_label.bind("<Button-1>", self._handle_click)

    def set_image(self, image: Image.Image):
        """Set the thumbnail image."""
        # Resize to fit
        image.thumbnail((120, 160), Image.Resampling.LANCZOS)
        self._photo_image = ImageTk.PhotoImage(image)
        self.image_label.configure(image=self._photo_image)

    def _handle_click(self, event=None):
        """Handle click event."""
        self.toggle_selection()
        if self.on_click:
            self.on_click(self.page_num, self.selected)

    def toggle_selection(self):
        """Toggle selection state."""
        self.selected = not self.selected
        self._update_appearance()

    def set_selected(self, selected: bool):
        """Set selection state."""
        self.selected = selected
        self._update_appearance()

    def _update_appearance(self):
        """Update visual appearance based on selection state."""
        if self.selected:
            self.configure(fg_color=("#3b8ed0", "#1f6aa5"))
        else:
            self.configure(fg_color=("gray85", "gray20"))


class PageSelectorDialog(ctk.CTkToplevel):
    """Dialog for selecting pages to remove."""

    def __init__(
        self,
        master,
        pdf_path: str,
        initial_selection: Optional[set[int]] = None,
        **kwargs
    ):
        super().__init__(master, **kwargs)

        self.pdf_path = pdf_path
        self.selected_pages: set[int] = initial_selection.copy() if initial_selection else set()
        self.thumbnails: list[PageThumbnail] = []
        self.result: Optional[set[int]] = None

        # Window setup
        self.title("Select Pages to Remove")
        self.geometry("600x500")
        self.resizable(True, True)

        # Make modal
        self.transient(master)
        self.grab_set()

        # Header
        header_frame = ctk.CTkFrame(self, fg_color="transparent")
        header_frame.pack(fill="x", padx=20, pady=(20, 10))

        self.title_label = ctk.CTkLabel(
            header_frame,
            text="Click pages to select for removal",
            font=ctk.CTkFont(size=16, weight="bold"),
        )
        self.title_label.pack(side="left")

        self.count_label = ctk.CTkLabel(
            header_frame,
            text="0 selected",
            font=ctk.CTkFont(size=13),
            text_color=("gray50", "gray60"),
        )
        self.count_label.pack(side="right")

        # Scrollable frame for thumbnails
        self.scroll_frame = ctk.CTkScrollableFrame(
            self,
            fg_color="transparent",
        )
        self.scroll_frame.pack(fill="both", expand=True, padx=20, pady=10)

        # Grid container
        self.grid_frame = ctk.CTkFrame(self.scroll_frame, fg_color="transparent")
        self.grid_frame.pack(fill="both", expand=True)

        # Loading label
        self.loading_label = ctk.CTkLabel(
            self.grid_frame,
            text="Loading thumbnails...",
            font=ctk.CTkFont(size=14),
        )
        self.loading_label.pack(pady=50)

        # Button frame
        button_frame = ctk.CTkFrame(self, fg_color="transparent")
        button_frame.pack(fill="x", padx=20, pady=20)

        self.cancel_btn = ctk.CTkButton(
            button_frame,
            text="Cancel",
            width=100,
            fg_color="transparent",
            border_width=1,
            text_color=("gray10", "gray90"),
            command=self._on_cancel,
        )
        self.cancel_btn.pack(side="left")

        self.select_all_btn = ctk.CTkButton(
            button_frame,
            text="Select All",
            width=100,
            fg_color="transparent",
            border_width=1,
            text_color=("gray10", "gray90"),
            command=self._on_select_all,
        )
        self.select_all_btn.pack(side="left", padx=(10, 0))

        self.clear_btn = ctk.CTkButton(
            button_frame,
            text="Clear All",
            width=100,
            fg_color="transparent",
            border_width=1,
            text_color=("gray10", "gray90"),
            command=self._on_clear_all,
        )
        self.clear_btn.pack(side="left", padx=(10, 0))

        self.confirm_btn = ctk.CTkButton(
            button_frame,
            text="Confirm",
            width=100,
            command=self._on_confirm,
        )
        self.confirm_btn.pack(side="right")

        # Load thumbnails in background
        self._load_thumbnails()

        # Update selection count
        self._update_count()

    def _load_thumbnails(self):
        """Load page thumbnails in background thread."""
        def load():
            try:
                with PDFAnalyzer(self.pdf_path) as analyzer:
                    page_count = analyzer.get_page_count()
                    thumbnails_data = []

                    for i in range(page_count):
                        img = analyzer.get_page_thumbnail(i, max_size=120)
                        thumbnails_data.append((i, img))

                # Update UI on main thread
                self.after(0, lambda: self._display_thumbnails(thumbnails_data))

            except Exception as e:
                self.after(0, lambda: self._show_error(str(e)))

        thread = threading.Thread(target=load, daemon=True)
        thread.start()

    def _display_thumbnails(self, thumbnails_data: list[tuple[int, Image.Image]]):
        """Display thumbnails in grid."""
        self.loading_label.destroy()

        # Calculate columns based on window width
        cols = 4

        for i, (page_num, img) in enumerate(thumbnails_data):
            row = i // cols
            col = i % cols

            thumbnail = PageThumbnail(
                self.grid_frame,
                page_num=page_num,
                image=img,
                selected=page_num in self.selected_pages,
                on_click=self._on_thumbnail_click,
            )
            thumbnail.grid(row=row, column=col, padx=5, pady=5)
            self.thumbnails.append(thumbnail)

    def _show_error(self, message: str):
        """Show error message."""
        self.loading_label.configure(text=f"Error: {message}")

    def _on_thumbnail_click(self, page_num: int, selected: bool):
        """Handle thumbnail click."""
        if selected:
            self.selected_pages.add(page_num)
        else:
            self.selected_pages.discard(page_num)
        self._update_count()

    def _update_count(self):
        """Update selection count display."""
        count = len(self.selected_pages)
        self.count_label.configure(text=f"{count} selected")

    def _on_select_all(self):
        """Select all pages."""
        for thumb in self.thumbnails:
            thumb.set_selected(True)
            self.selected_pages.add(thumb.page_num)
        self._update_count()

    def _on_clear_all(self):
        """Clear all selections."""
        for thumb in self.thumbnails:
            thumb.set_selected(False)
        self.selected_pages.clear()
        self._update_count()

    def _on_cancel(self):
        """Cancel and close dialog."""
        self.result = None
        self.destroy()

    def _on_confirm(self):
        """Confirm selection and close dialog."""
        self.result = self.selected_pages.copy()
        self.destroy()

    def get_result(self) -> Optional[set[int]]:
        """Get the selection result after dialog closes."""
        self.wait_window()
        return self.result
