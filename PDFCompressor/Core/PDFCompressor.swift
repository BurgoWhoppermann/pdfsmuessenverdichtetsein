import Foundation
import PDFKit
import Quartz
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Data Types

enum CompressionMode: String, CaseIterable, Identifiable {
    /// Re-encodes the images inside the PDF through a Quartz filter. Text stays text.
    case keepText
    /// Renders every page to a JPEG. Smallest files, but text is lost.
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepText: return "Keep text"
        case .maximum: return "Maximum compression"
        }
    }

    var detail: String {
        switch self {
        case .keepText:
            return "Keep text (recommended): Text stays selectable and searchable. Only images are compressed."
        case .maximum:
            return "Maximum compression: Every page becomes a picture. Smallest files, but text can no longer be selected, copied or searched."
        }
    }

    /// Replaces `detail` for Maximum compression when the invisible text layer is on.
    static let maximumWithTextLayerDetail = "Maximum compression: Every page becomes a picture, with the text laid invisibly on top. Text stays selectable, copyable and searchable, and the file stays small."
}

struct CompressionResult {
    let success: Bool
    let outputURL: URL?
    let originalSize: Int64
    let finalSize: Int64
    var compressionRatio: Double {
        guard originalSize > 0 else { return 0 }
        return Double(finalSize) / Double(originalSize) * 100
    }
    let message: String
    var mode: CompressionMode = .keepText
    /// False when the output is the smallest the mode can produce but still above the target.
    var targetReached: Bool = true
}

struct CompressionOptions {
    var targetPercentage: Int = 50
    var grayscale: Bool = false
    var pagesToRemove: Set<Int> = []
    var mode: CompressionMode = .keepText
    /// Maximum compression only: lay the page's text invisibly over the picture, so it stays selectable and searchable.
    var keepTextLayer: Bool = true
}

// MARK: - Page Geometry

extension PDFPage {
    /// Size of the page as a viewer shows it: crop box, with a 90/270 degree rotation applied.
    var displaySize: CGSize {
        let box = bounds(for: .cropBox)
        return abs(rotation) % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }
}

// MARK: - DPI Thresholds

private let dpiThresholds: [(threshold: Int, dpi: CGFloat)] = [
    (80, 150),
    (50, 120),
    (30, 100),
    (10, 72),
    (0, 50),
]

private func selectDPI(for targetPercentage: Int) -> CGFloat {
    for (threshold, dpi) in dpiThresholds {
        if targetPercentage >= threshold {
            return dpi
        }
    }
    return 50
}

// MARK: - Keep text: Quartz filter

enum QuartzCompression {

    /// Writes `document` through a Quartz filter that re-encodes images as JPEG. Text and vectors are left alone.
    static func data(for document: PDFDocument, dpi: CGFloat, quality: Int, grayscale: Bool) -> Data? {
        let tmp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        let filterURL = tmp.appendingPathComponent("\(id).qfilter")
        let pdfURL = tmp.appendingPathComponent("\(id).pdf")
        defer {
            try? FileManager.default.removeItem(at: filterURL)
            try? FileManager.default.removeItem(at: pdfURL)
        }

        guard let plist = filterPlist(dpi: dpi, quality: quality, grayscale: grayscale),
              (plist as NSDictionary).write(to: filterURL, atomically: true),
              let filter = QuartzFilter(url: filterURL) else { return nil }

        let writeOptions: [PDFDocumentWriteOption: Any] = [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]
        guard document.write(to: pdfURL, withOptions: writeOptions) else { return nil }
        return try? Data(contentsOf: pdfURL)
    }

    /// Same structure as the system "Reduce File Size" filter. For grayscale the colour profile
    /// is taken from the system "Black & White" filter instead of being rebuilt.
    private static func filterPlist(dpi: CGFloat, quality: Int, grayscale: Bool) -> [String: Any]? {
        let imageSettings: [String: Any] = [
            "Compression Quality": Double(quality) / 100.0,
            "ImageCompression": "ImageJPEGCompress",
            "ImageScaleSettings": [
                "ImageResolution": Int(dpi),
                "ImageScaleInterpolate": true,
                "ImageSizeMax": 100_000,
                "ImageSizeMin": 0,
            ] as [String: Any],
        ]

        var plist: [String: Any]
        if grayscale {
            guard let template = NSDictionary(contentsOfFile: "/System/Library/Filters/Black & White.qfilter") as? [String: Any]
            else { return nil }
            plist = template
        } else {
            plist = ["FilterType": 1, "Domains": ["Applications": true, "Printing": true]]
        }

        var filterData = plist["FilterData"] as? [String: Any] ?? [:]
        var colorSettings = filterData["ColorSettings"] as? [String: Any] ?? [:]
        colorSettings["ImageSettings"] = imageSettings
        filterData["ColorSettings"] = colorSettings
        plist["FilterData"] = filterData
        plist["Name"] = "PDFCompressor"
        return plist
    }
}

// MARK: - Maximum compression: invisible text layer

enum InvisibleTextLayer {

    /// Draws the text of `page` into `context` as invisible text, line by line, stretched over the box where
    /// the page shows that line. The context is expected to be in the page's display space (crop box origin
    /// at 0,0, rotation applied), the same space `page.displaySize` describes.
    ///
    /// Lines come from PDFKit's line selections. Per-character bounds are not used: on some PDFs they report
    /// zero heights and wrong sizes, which loses letters.
    static func draw(_ page: PDFPage, in context: CGContext) {
        let box = page.bounds(for: .cropBox)
        guard let selection = page.selection(for: box) else { return }
        let rotation = ((page.rotation % 360) + 360) % 360

        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.setFillColor(CGColor(gray: 0, alpha: 1))

        for line in selection.selectionsByLine() {
            // Embedded images show up as U+FFFC. They are no text.
            let string = (line.string ?? "")
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bounds = line.bounds(for: page)
            guard !string.isEmpty, bounds.width > 0, bounds.height > 0 else { continue }
            let rect = display(bounds, cropBox: box, rotation: rotation)
            guard rect.intersects(CGRect(origin: .zero, size: page.displaySize)) else { continue }
            drawLine(string, in: rect, context: context)
        }
        context.restoreGState()
    }

    /// Maps a rectangle from page space (as PDFKit reports it) to display space.
    private static func display(_ r: CGRect, cropBox b: CGRect, rotation: Int) -> CGRect {
        let x0 = r.minX - b.minX, x1 = r.maxX - b.minX
        let y0 = r.minY - b.minY, y1 = r.maxY - b.minY
        switch rotation {
        case 90:  return CGRect(x: y0, y: b.width - x1, width: y1 - y0, height: x1 - x0)
        case 180: return CGRect(x: b.width - x1, y: b.height - y1, width: x1 - x0, height: y1 - y0)
        case 270: return CGRect(x: b.height - y1, y: x0, width: y1 - y0, height: x1 - x0)
        default:  return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }

    /// Draws `string` stretched to fill `rect`. Text that runs vertically is turned to follow its box.
    private static func drawLine(_ string: String, in rect: CGRect, context: CGContext) {
        let vertical = rect.height > rect.width * 1.5 && string.count > 1
        let length = vertical ? rect.height : rect.width
        let thickness = vertical ? rect.width : rect.height

        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTLigatureAttributeName as String): 0,
        ]
        let measured = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        let naturalWidth = CTLineGetTypographicBounds(measured, nil, nil, nil)
        guard naturalWidth > 0 else { return }
        // The trailing space sits just past the box. It keeps neighbouring lines apart when text is extracted.
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string + " ", attributes: attributes))

        // The font is 10 pt; scale it so its ascent + descent fills the box across, and the line fills it along.
        let scaleY = thickness / (CTFontGetAscent(font) + CTFontGetDescent(font))
        let scaleX = length / naturalWidth
        let descent = CTFontGetDescent(font) * scaleY

        // The stretch goes through the CTM: a non-uniform text matrix is not written to the PDF as such.
        context.saveGState()
        if vertical {
            // Text reads bottom to top.
            context.translateBy(x: rect.maxX - descent, y: rect.minY)
            context.rotate(by: .pi / 2)
        } else {
            context.translateBy(x: rect.minX, y: rect.minY + descent)
        }
        context.scaleBy(x: scaleX, y: scaleY)
        context.textMatrix = .identity
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

// MARK: - PDF Compressor

class PDFCompressionEngine {

    typealias ProgressCallback = (String, Int) -> Void

    private let inputURL: URL
    private let outputURL: URL
    private let options: CompressionOptions
    private let progressCallback: ProgressCallback

    private struct SearchOutcome {
        let data: Data
        let reachedTarget: Bool
    }

    private let lowestDPI: CGFloat = 50
    private let lowestQuality = 5
    private let highestQuality = 95

    init(inputURL: URL, outputURL: URL, options: CompressionOptions, progressCallback: @escaping ProgressCallback) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.options = options
        self.progressCallback = progressCallback
    }

    func compress() -> CompressionResult {
        let originalSize = fileSize(at: inputURL)
        let mode = options.mode

        progressCallback("Opening PDF...", 5)

        guard let sourceDocument = PDFDocument(url: inputURL) else {
            return failure(originalSize, "Could not open PDF")
        }
        // Pages only keep a weak reference to their document, so it has to outlive page copying and drawing.
        defer { withExtendedLifetime(sourceDocument) {} }

        let workingDocument: PDFDocument
        if !options.pagesToRemove.isEmpty {
            workingDocument = removePages(from: sourceDocument, pages: options.pagesToRemove)
        } else {
            workingDocument = sourceDocument
        }

        guard workingDocument.pageCount > 0 else {
            return failure(originalSize, "No pages left. Deselect at least one page to keep.")
        }

        let targetSize = Int64(Double(originalSize) * Double(options.targetPercentage) / 100.0)

        progressCallback(mode == .keepText ? "Compressing images..." : "Rendering pages...", 10)

        let outcome: SearchOutcome?
        switch mode {
        case .keepText:
            outcome = search(targetSize: targetSize) { dpi, quality in
                QuartzCompression.data(for: workingDocument, dpi: dpi, quality: quality, grayscale: self.options.grayscale)
            }
        case .maximum:
            outcome = search(targetSize: targetSize) { dpi, quality in
                self.renderDocumentAsJPEG(document: workingDocument, dpi: dpi, quality: quality)
            }
        }

        guard let outcome else {
            return failure(originalSize, mode == .keepText && options.grayscale
                ? "Could not apply the grayscale filter. Try Maximum compression."
                : "Compression failed")
        }

        // Keep text can make text-only PDFs bigger. Never hand back a larger file than the input.
        var data = outcome.data
        var message = outcome.reachedTarget ? "Compression successful" : "Target size not reached"
        var reached = outcome.reachedTarget
        let untouched = options.pagesToRemove.isEmpty && !options.grayscale
        if mode == .keepText, untouched, Int64(data.count) >= originalSize,
           let original = try? Data(contentsOf: inputURL) {
            data = original
            reached = false
            message = "This PDF has little to compress while keeping its text"
        }

        do {
            try data.write(to: outputURL)
        } catch {
            return failure(originalSize, "Could not save the file: \(error.localizedDescription)")
        }

        progressCallback("Done!", 100)
        return CompressionResult(success: true, outputURL: outputURL, originalSize: originalSize,
                                 finalSize: Int64(data.count), message: message, mode: mode, targetReached: reached)
    }

    private func failure(_ originalSize: Int64, _ message: String) -> CompressionResult {
        CompressionResult(success: false, outputURL: nil, originalSize: originalSize, finalSize: 0,
                          message: message, mode: options.mode, targetReached: false)
    }

    // MARK: - Page Removal

    private func removePages(from document: PDFDocument, pages: Set<Int>) -> PDFDocument {
        let newDoc = PDFDocument()
        var insertIndex = 0
        for i in 0..<document.pageCount {
            if !pages.contains(i) {
                if let page = document.page(at: i) {
                    newDoc.insert(page, at: insertIndex)
                    insertIndex += 1
                }
            }
        }
        return newDoc
    }

    // MARK: - Search for DPI and quality

    /// Finds the best-looking setting that stays at or below `targetSize`.
    /// Checks the smallest possible output first, so an unreachable target costs one pass instead of dozens.
    private func search(targetSize: Int64, render: (CGFloat, Int) -> Data?) -> SearchOutcome? {
        progressCallback("Checking the smallest possible size...", 12)
        guard let floor = render(lowestDPI, lowestQuality) else { return nil }
        if Int64(floor.count) > targetSize {
            return SearchOutcome(data: floor, reachedTarget: false)
        }

        let startDPI = selectDPI(for: options.targetPercentage)
        let dpis = [startDPI] + dpiThresholds.map { $0.dpi }.filter { $0 < startDPI }
        var step = 0

        for dpi in dpis {
            var low = lowestQuality
            var high = highestQuality
            var best: Data? = nil
            var bestQuality = 0

            while low <= high {
                let mid = (low + high) / 2
                step += 1
                progressCallback("Using DPI=\(Int(dpi)), trying quality=\(mid)%...", min(15 + step * 6, 90))

                guard let data = render(dpi, mid) else { high = mid - 1; continue }
                let size = Int64(data.count)

                if size <= targetSize {
                    // Close enough to the target: stop early.
                    if Double(size) >= Double(targetSize) * 0.95 { return SearchOutcome(data: data, reachedTarget: true) }
                    if best == nil || data.count > best!.count { best = data; bestQuality = mid }
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }

            if var best {
                // Top quality still fits: the DPI step was the limit, so spend the spare room on resolution.
                if dpi == startDPI && bestQuality == highestQuality {
                    for higher in [200, 300] as [CGFloat] where higher > startDPI {
                        step += 1
                        progressCallback("Using DPI=\(Int(higher)), trying quality=\(highestQuality)%...", min(15 + step * 6, 90))
                        guard let data = render(higher, highestQuality), Int64(data.count) <= targetSize else { break }
                        best = data
                    }
                }
                return SearchOutcome(data: best, reachedTarget: true)
            }
        }

        return SearchOutcome(data: floor, reachedTarget: true)
    }

    // MARK: - Maximum compression: render pages as JPEG into a new PDF

    private func renderDocumentAsJPEG(document: PDFDocument, dpi: CGFloat, quality: Int) -> Data? {
        let mutableData = NSMutableData()

        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else { return nil }

        // We need to create the PDF context with the first page's box
        guard let firstPage = document.page(at: 0) else { return nil }
        var firstBox = CGRect(origin: .zero, size: firstPage.displaySize)

        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else { return nil }

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }

            let pageSize = page.displaySize
            let scale = dpi / 72.0
            let pixelWidth = Int(pageSize.width * scale)
            let pixelHeight = Int(pageSize.height * scale)

            // Render page to bitmap
            let colorSpace: CGColorSpace = options.grayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let componentsPerPixel = options.grayscale ? 1 : 4
            let bytesPerRow = pixelWidth * componentsPerPixel
            let bitmapInfo: UInt32 = options.grayscale
                ? CGImageAlphaInfo.none.rawValue
                : CGImageAlphaInfo.premultipliedLast.rawValue

            guard let bitmapContext = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { continue }

            bitmapContext.setFillColor(options.grayscale ? CGColor(gray: 1.0, alpha: 1.0) : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            bitmapContext.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            bitmapContext.scaleBy(x: scale, y: scale)
            page.draw(with: .cropBox, to: bitmapContext)

            guard let cgImage = bitmapContext.makeImage() else { continue }

            // Compress to JPEG
            guard let jpegData = jpegData(from: cgImage, quality: quality) else { continue }

            // Decode JPEG back to CGImage
            guard let jpegSource = CGImageSourceCreateWithData(jpegData as CFData, nil),
                  let jpegImage = CGImageSourceCreateImageAtIndex(jpegSource, 0, nil) else { continue }

            // Begin PDF page
            var pageBox = CGRect(origin: .zero, size: pageSize)
            pdfContext.beginPage(mediaBox: &pageBox)

            // Draw the JPEG image filling the page
            pdfContext.draw(jpegImage, in: pageBox)

            if options.keepTextLayer {
                InvisibleTextLayer.draw(page, in: pdfContext)
            }

            pdfContext.endPage()
        }

        pdfContext.closePDF()

        if mutableData.length > 0 {
            return mutableData as Data
        }
        return nil
    }

    private func jpegData(from image: CGImage, quality: Int) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: - Utilities

    private func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}
