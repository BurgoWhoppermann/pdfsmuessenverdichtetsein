"""Main application class for PDF Compressor."""

import customtkinter as ctk
from ui.main_window import MainWindow


class PDFCompressorApp:
    """Main application class."""

    def __init__(self):
        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")
        self.window = MainWindow()

    def run(self):
        """Start the application."""
        self.window.mainloop()
