# pdfsmuessenverdichtetsein
PDFs verdichten is a simple macOS tool to compress PDF files. Set a target size, optionally convert to grayscale or remove specific pages, and export a smaller PDF. No login, no accounts, no purchases!

## Two modes

- **Keep text** (default): Text stays selectable and searchable. Only the images inside the PDF are re-encoded and downscaled. If the PDF is mostly text or vector graphics, there may be little to gain.
- **Maximum compression**: Every page is rendered to a picture. Smallest files for scans and image-heavy PDFs, but with the option "Keep text selectable" switched off, text can no longer be selected, copied or searched. With it on (the default), the page's text is laid invisibly over the picture, so selecting, copying and searching still work, for about 0.5% more file size. For text or vector PDFs the result can even be bigger than the original.

PDFs without a text layer (scans) start in Maximum compression, because there is no text to keep.

The target size is a ceiling: the app picks the best quality that still fits. If the target is out of reach, you get the smallest result the mode can produce, plus a hint and a button to switch modes.
