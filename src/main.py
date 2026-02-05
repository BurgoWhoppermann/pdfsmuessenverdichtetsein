#!/usr/bin/env python3
"""PDF Compressor - Entry point."""

import sys
import os

# Add src to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app import PDFCompressorApp


def main():
    app = PDFCompressorApp()
    app.run()


if __name__ == "__main__":
    main()
