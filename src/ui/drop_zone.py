"""Drag-and-drop zone widget."""

import customtkinter as ctk
from tkinter import filedialog
from typing import Callable, Optional
from pathlib import Path

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
    DND_AVAILABLE = True
except ImportError:
    DND_AVAILABLE = False


class DropZone(ctk.CTkFrame):
    """A drag-and-drop zone for PDF files."""

    def __init__(
        self,
        master,
        on_file_dropped: Callable[[str], None],
        **kwargs
    ):
        """
        Args:
            master: Parent widget
            on_file_dropped: Callback when a file is dropped/selected
        """
        super().__init__(master, **kwargs)

        self.on_file_dropped = on_file_dropped
        self.current_file: Optional[Path] = None

        # Configure appearance
        self.configure(
            fg_color=("gray90", "gray17"),
            corner_radius=10,
        )

        # Create inner frame with dashed border effect
        self.inner_frame = ctk.CTkFrame(
            self,
            fg_color="transparent",
            corner_radius=8,
        )
        self.inner_frame.pack(expand=True, fill="both", padx=3, pady=3)

        # Icon/label
        self.icon_label = ctk.CTkLabel(
            self.inner_frame,
            text="📄",
            font=ctk.CTkFont(size=48),
        )
        self.icon_label.pack(pady=(30, 10))

        # Main text
        self.main_label = ctk.CTkLabel(
            self.inner_frame,
            text="Drop PDF here",
            font=ctk.CTkFont(size=18, weight="bold"),
        )
        self.main_label.pack(pady=(0, 5))

        # Sub text
        self.sub_label = ctk.CTkLabel(
            self.inner_frame,
            text="or click to browse",
            font=ctk.CTkFont(size=12),
            text_color=("gray50", "gray60"),
        )
        self.sub_label.pack(pady=(0, 30))

        # File info (hidden initially)
        self.file_info_frame = ctk.CTkFrame(
            self.inner_frame,
            fg_color="transparent",
        )

        self.filename_label = ctk.CTkLabel(
            self.file_info_frame,
            text="",
            font=ctk.CTkFont(size=14),
            wraplength=250,
        )
        self.filename_label.pack()

        self.filesize_label = ctk.CTkLabel(
            self.file_info_frame,
            text="",
            font=ctk.CTkFont(size=12),
            text_color=("gray50", "gray60"),
        )
        self.filesize_label.pack()

        # Bind click events
        self.bind("<Button-1>", self._on_click)
        self.inner_frame.bind("<Button-1>", self._on_click)
        self.icon_label.bind("<Button-1>", self._on_click)
        self.main_label.bind("<Button-1>", self._on_click)
        self.sub_label.bind("<Button-1>", self._on_click)

        # Setup drag and drop if available
        self._setup_dnd()

    def _setup_dnd(self):
        """Setup drag-and-drop functionality."""
        if not DND_AVAILABLE:
            return

        try:
            # Register as drop target
            self.drop_target_register(DND_FILES)
            self.dnd_bind("<<Drop>>", self._on_drop)
            self.dnd_bind("<<DragEnter>>", self._on_drag_enter)
            self.dnd_bind("<<DragLeave>>", self._on_drag_leave)
        except Exception:
            # DnD not properly initialized
            pass

    def _on_drag_enter(self, event):
        """Handle drag enter event."""
        self.configure(fg_color=("gray80", "gray25"))
        return event.action

    def _on_drag_leave(self, event):
        """Handle drag leave event."""
        self.configure(fg_color=("gray90", "gray17"))
        return event.action

    def _on_drop(self, event):
        """Handle file drop event."""
        self.configure(fg_color=("gray90", "gray17"))

        # Parse dropped files (handle curly braces for paths with spaces)
        files = self._parse_drop_data(event.data)

        if files:
            file_path = files[0]
            if file_path.lower().endswith(".pdf"):
                self._set_file(file_path)

        return event.action

    def _parse_drop_data(self, data: str) -> list[str]:
        """Parse dropped file data from DnD event."""
        files = []
        # Handle paths with spaces (wrapped in curly braces on macOS)
        if data.startswith("{"):
            # Multiple files or path with spaces
            import re
            files = re.findall(r'\{([^}]+)\}', data)
            if not files:
                files = [data.strip("{}")]
        else:
            files = data.split()
        return files

    def _on_click(self, event=None):
        """Handle click to browse for file."""
        file_path = filedialog.askopenfilename(
            title="Select PDF file",
            filetypes=[("PDF files", "*.pdf"), ("All files", "*.*")],
        )
        if file_path:
            self._set_file(file_path)

    def _set_file(self, file_path: str):
        """Set the current file and update display."""
        self.current_file = Path(file_path)

        # Update display
        self.icon_label.configure(text="✅")
        self.main_label.configure(text=self.current_file.name)
        self.sub_label.configure(text="Click to change file")

        # Show file info
        size_mb = self.current_file.stat().st_size / (1024 * 1024)
        self.filesize_label.configure(text=f"{size_mb:.2f} MB")
        self.file_info_frame.pack(pady=(0, 20))

        # Notify callback
        self.on_file_dropped(str(self.current_file))

    def reset(self):
        """Reset to initial state."""
        self.current_file = None
        self.icon_label.configure(text="📄")
        self.main_label.configure(text="Drop PDF here")
        self.sub_label.configure(text="or click to browse")
        self.file_info_frame.pack_forget()

    def get_file_path(self) -> Optional[str]:
        """Get the current file path."""
        return str(self.current_file) if self.current_file else None
