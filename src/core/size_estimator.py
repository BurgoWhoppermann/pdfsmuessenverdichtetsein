"""Target size estimation and quality selection."""

from dataclasses import dataclass


@dataclass
class QualityPreset:
    """Represents a compression quality preset."""
    name: str
    dpi: int
    jpeg_quality: int


# Quality presets from highest to lowest
QUALITY_PRESETS = [
    QualityPreset("High", 300, 95),
    QualityPreset("Medium-High", 200, 85),
    QualityPreset("Medium", 150, 75),
    QualityPreset("Low", 100, 60),
    QualityPreset("Very Low", 72, 45),
]


class SizeEstimator:
    """Estimates compression settings to achieve target file size."""

    def __init__(self, original_size: int):
        """
        Args:
            original_size: Original file size in bytes
        """
        self.original_size = original_size

    def get_target_size(self, percentage: int) -> int:
        """Calculate target size in bytes from percentage.

        Args:
            percentage: Target size as percentage of original (10-100)
        """
        return int(self.original_size * (percentage / 100))

    def get_target_size_mb(self, percentage: int) -> float:
        """Calculate target size in MB from percentage."""
        return self.get_target_size(percentage) / (1024 * 1024)

    def estimate_preset_for_target(self, target_percentage: int) -> QualityPreset:
        """Estimate the best quality preset to achieve target size.

        This is a heuristic - actual compression will test iteratively.

        Args:
            target_percentage: Target size as percentage of original

        Returns:
            Recommended starting quality preset
        """
        # Simple heuristic mapping percentage to preset index
        if target_percentage >= 80:
            return QUALITY_PRESETS[0]
        elif target_percentage >= 60:
            return QUALITY_PRESETS[1]
        elif target_percentage >= 40:
            return QUALITY_PRESETS[2]
        elif target_percentage >= 25:
            return QUALITY_PRESETS[3]
        else:
            return QUALITY_PRESETS[4]

    def get_presets_for_iterative_compression(self) -> list[QualityPreset]:
        """Get all presets for iterative compression testing."""
        return QUALITY_PRESETS.copy()
