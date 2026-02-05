"""Target size slider widget."""

import customtkinter as ctk
from typing import Callable, Optional


class SizeSlider(ctk.CTkFrame):
    """Slider for selecting target compression size."""

    # Color constants for estimate status
    COLOR_GREEN = "#22c55e"   # Under target
    COLOR_ORANGE = "#f97316"  # Close to target
    COLOR_RED = "#ef4444"     # Over target
    COLOR_GRAY = ("gray50", "gray60")  # Loading/neutral

    def __init__(
        self,
        master,
        on_value_changed: Optional[Callable[[int], None]] = None,
        **kwargs
    ):
        """
        Args:
            master: Parent widget
            on_value_changed: Callback when slider value changes
        """
        super().__init__(master, fg_color="transparent", **kwargs)

        self.on_value_changed = on_value_changed
        self.original_size_mb: float = 0.0
        self._estimated_bytes: Optional[int] = None

        # Title
        self.title_label = ctk.CTkLabel(
            self,
            text="Target Size",
            font=ctk.CTkFont(size=14, weight="bold"),
        )
        self.title_label.pack(anchor="w", pady=(0, 5))

        # Slider frame
        self.slider_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.slider_frame.pack(fill="x", pady=(0, 5))

        # Min label
        self.min_label = ctk.CTkLabel(
            self.slider_frame,
            text="10%",
            font=ctk.CTkFont(size=11),
            text_color=("gray50", "gray60"),
        )
        self.min_label.pack(side="left")

        # Slider
        self.slider = ctk.CTkSlider(
            self.slider_frame,
            from_=10,
            to=100,
            number_of_steps=90,
            command=self._on_slider_change,
        )
        self.slider.set(50)
        self.slider.pack(side="left", fill="x", expand=True, padx=10)

        # Max label
        self.max_label = ctk.CTkLabel(
            self.slider_frame,
            text="100%",
            font=ctk.CTkFont(size=11),
            text_color=("gray50", "gray60"),
        )
        self.max_label.pack(side="left")

        # Info frame
        self.info_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.info_frame.pack(fill="x")

        # Current value display
        self.value_label = ctk.CTkLabel(
            self.info_frame,
            text="Target: 50%",
            font=ctk.CTkFont(size=13),
        )
        self.value_label.pack(side="left")


        # Estimated result display
        self.estimate_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.estimate_frame.pack(fill="x", pady=(5, 0))

        self.estimate_label = ctk.CTkLabel(
            self.estimate_frame,
            text="",
            font=ctk.CTkFont(size=12),
            text_color=self.COLOR_GRAY,
        )
        self.estimate_label.pack(side="left")

    def _on_slider_change(self, value: float):
        """Handle slider value change."""
        percentage = int(value)
        self.value_label.configure(text=f"Target: {percentage}%")

        if self.on_value_changed:
            self.on_value_changed(percentage)

    def set_original_size(self, size_mb: float):
        """Set the original file size for reference.

        Args:
            size_mb: Original file size in megabytes
        """
        self.original_size_mb = size_mb
        self._on_slider_change(self.slider.get())

    def get_value(self) -> int:
        """Get current slider value as percentage."""
        return int(self.slider.get())

    def set_estimate_loading(self):
        """Show loading indicator for estimate."""
        if self.original_size_mb > 0:
            self.estimate_label.configure(
                text="Estimated result: calculating...",
                text_color=self.COLOR_GRAY,
            )

    def set_estimate(self, estimated_bytes: int):
        """Set the estimated result size.

        Args:
            estimated_bytes: Estimated compressed size in bytes
        """
        self._estimated_bytes = estimated_bytes
        estimated_mb = estimated_bytes / (1024 * 1024)

        # Calculate target size for comparison
        target_mb = self.original_size_mb * (self.get_value() / 100)

        # Determine color based on estimate vs target
        if estimated_mb <= target_mb * 0.95:
            color = self.COLOR_GREEN
        elif estimated_mb <= target_mb * 1.05:
            color = self.COLOR_ORANGE
        else:
            color = self.COLOR_RED

        self.estimate_label.configure(
            text=f"Estimated result: ~{estimated_mb:.2f} MB",
            text_color=color,
        )

    def clear_estimate(self):
        """Clear the estimate display."""
        self._estimated_bytes = None
        self.estimate_label.configure(text="", text_color=self.COLOR_GRAY)

    def reset(self):
        """Reset to default state."""
        self.slider.set(50)
        self.original_size_mb = 0.0
        self._estimated_bytes = None
        self.value_label.configure(text="Target: 50%")
        self.estimate_label.configure(text="", text_color=self.COLOR_GRAY)
