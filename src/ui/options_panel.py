"""Compression options panel widget."""

import customtkinter as ctk
from typing import Callable, Optional


class OptionsPanel(ctk.CTkFrame):
    """Panel with compression options (grayscale, page removal)."""

    def __init__(
        self,
        master,
        on_page_select_clicked: Optional[Callable[[], None]] = None,
        on_grayscale_changed: Optional[Callable[[bool], None]] = None,
        **kwargs
    ):
        """
        Args:
            master: Parent widget
            on_page_select_clicked: Callback when page selection is requested
            on_grayscale_changed: Callback when grayscale option changes
        """
        super().__init__(master, fg_color="transparent", **kwargs)

        self.on_page_select_clicked = on_page_select_clicked
        self.on_grayscale_changed = on_grayscale_changed
        self.selected_pages: set[int] = set()

        # Title
        self.title_label = ctk.CTkLabel(
            self,
            text="Options",
            font=ctk.CTkFont(size=14, weight="bold"),
        )
        self.title_label.pack(anchor="w", pady=(0, 10))

        # Grayscale option
        self.grayscale_var = ctk.BooleanVar(value=False)
        self.grayscale_check = ctk.CTkCheckBox(
            self,
            text="Convert to grayscale (B&W)",
            variable=self.grayscale_var,
            font=ctk.CTkFont(size=13),
            command=self._on_grayscale_toggle,
        )
        self.grayscale_check.pack(anchor="w", pady=(0, 8))

        # Page removal option frame
        self.page_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.page_frame.pack(anchor="w", fill="x")

        self.remove_pages_var = ctk.BooleanVar(value=False)
        self.remove_pages_check = ctk.CTkCheckBox(
            self.page_frame,
            text="Remove specific pages",
            variable=self.remove_pages_var,
            font=ctk.CTkFont(size=13),
            command=self._on_remove_pages_toggle,
        )
        self.remove_pages_check.pack(side="left")

        # Select pages button (initially disabled)
        self.select_btn = ctk.CTkButton(
            self.page_frame,
            text="Select...",
            width=80,
            height=28,
            font=ctk.CTkFont(size=12),
            command=self._on_select_pages,
            state="disabled",
        )
        self.select_btn.pack(side="left", padx=(10, 0))

        # Selection info label
        self.selection_label = ctk.CTkLabel(
            self,
            text="",
            font=ctk.CTkFont(size=11),
            text_color=("gray50", "gray60"),
        )
        self.selection_label.pack(anchor="w", padx=(26, 0))

    def _on_grayscale_toggle(self):
        """Handle grayscale checkbox toggle."""
        if self.on_grayscale_changed:
            self.on_grayscale_changed(self.grayscale_var.get())

    def _on_remove_pages_toggle(self):
        """Handle remove pages checkbox toggle."""
        if self.remove_pages_var.get():
            self.select_btn.configure(state="normal")
            if self.on_page_select_clicked and not self.selected_pages:
                self.on_page_select_clicked()
        else:
            self.select_btn.configure(state="disabled")
            self.selected_pages.clear()
            self.selection_label.configure(text="")

    def _on_select_pages(self):
        """Handle select pages button click."""
        if self.on_page_select_clicked:
            self.on_page_select_clicked()

    def set_selected_pages(self, pages: set[int]):
        """Set the selected pages and update display.

        Args:
            pages: Set of zero-indexed page numbers
        """
        self.selected_pages = pages.copy()

        if pages:
            # Display as 1-indexed for user
            page_list = sorted(p + 1 for p in pages)
            if len(page_list) <= 5:
                pages_str = ", ".join(str(p) for p in page_list)
            else:
                pages_str = f"{len(page_list)} pages selected"
            self.selection_label.configure(text=f"Selected: {pages_str}")
        else:
            self.selection_label.configure(text="")

    def get_grayscale(self) -> bool:
        """Get grayscale option value."""
        return self.grayscale_var.get()

    def get_pages_to_remove(self) -> set[int]:
        """Get set of pages to remove (zero-indexed)."""
        if self.remove_pages_var.get():
            return self.selected_pages.copy()
        return set()

    def set_enabled(self, enabled: bool):
        """Enable or disable all options."""
        state = "normal" if enabled else "disabled"
        self.grayscale_check.configure(state=state)
        self.remove_pages_check.configure(state=state)
        if enabled and self.remove_pages_var.get():
            self.select_btn.configure(state="normal")
        else:
            self.select_btn.configure(state="disabled")

    def reset(self):
        """Reset all options to default."""
        self.grayscale_var.set(False)
        self.remove_pages_var.set(False)
        self.selected_pages.clear()
        self.select_btn.configure(state="disabled")
        self.selection_label.configure(text="")
