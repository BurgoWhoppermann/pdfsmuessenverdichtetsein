import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Estimates the compressed file size without running the full search.
///
/// The engine looks for the best setting that stays at or below the target, so the result is one of three things:
/// the largest the mode can produce (target is generous), the smallest it can produce (target is out of reach),
/// or the target itself. The estimator measures the two extremes and picks accordingly.
class PreviewEstimator {

    private let pdfURL: URL

    /// Below this size Keep text runs the real filter over the whole file. Above it, three sample pages.
    private let wholeFileLimit: Int64 = 50 * 1024 * 1024

    init(url: URL) {
        self.pdfURL = url
    }

    /// Estimate compressed size in bytes.
    func estimateSize(targetPercentage: Int, grayscale: Bool, pagesToRemove: Set<Int>, mode: CompressionMode) -> Int64 {
        guard let document = PDFDocument(url: pdfURL) else { return 0 }

        let remaining = (0..<document.pageCount).filter { !pagesToRemove.contains($0) }
        guard !remaining.isEmpty else { return 0 }

        let originalSize = fileSize()
        let target = Int64(Double(originalSize) * Double(targetPercentage) / 100.0)

        // Mirrors the engine: top quality at the starting DPI, then 200 and 300 DPI while they still fit.
        let startDPI = selectDPI(for: targetPercentage)
        var largest = measure(document: document, pages: remaining, dpi: startDPI, quality: 95, grayscale: grayscale, mode: mode, originalSize: originalSize)
        if largest <= target {
            for higher in [200, 300] as [CGFloat] where higher > startDPI {
                let size = measure(document: document, pages: remaining, dpi: higher, quality: 95, grayscale: grayscale, mode: mode, originalSize: originalSize)
                guard size <= target else { break }
                largest = size
            }
        }
        let smallest = measure(document: document, pages: remaining, dpi: 50, quality: 5, grayscale: grayscale, mode: mode, originalSize: originalSize)

        var estimate: Int64
        if smallest > target {
            estimate = smallest
        } else if largest <= target {
            estimate = largest
        } else {
            estimate = target
        }

        // Keep text never returns a bigger file than the input when nothing else changes.
        if mode == .keepText && pagesToRemove.isEmpty && !grayscale {
            estimate = min(estimate, originalSize)
        }
        return estimate
    }

    // MARK: - Measuring

    private func measure(document: PDFDocument, pages: [Int], dpi: CGFloat, quality: Int,
                         grayscale: Bool, mode: CompressionMode, originalSize: Int64) -> Int64 {
        switch mode {
        case .keepText:
            return measureKeepingText(document: document, pages: pages, dpi: dpi, quality: quality,
                                      grayscale: grayscale, originalSize: originalSize)
        case .maximum:
            return measureRendered(document: document, pages: pages, dpi: dpi, quality: quality, grayscale: grayscale)
        }
    }

    private func measureKeepingText(document: PDFDocument, pages: [Int], dpi: CGFloat, quality: Int,
                                    grayscale: Bool, originalSize: Int64) -> Int64 {
        let wholeFile = originalSize <= wholeFileLimit
        let indices: [Int]
        if wholeFile {
            indices = pages
        } else {
            let count = min(3, pages.count)
            indices = (0..<count).map { pages[$0 * pages.count / count] }
        }

        let work = PDFDocument()
        for (i, index) in indices.enumerated() {
            if let page = document.page(at: index) { work.insert(page, at: i) }
        }
        guard work.pageCount > 0,
              let data = QuartzCompression.data(for: work, dpi: dpi, quality: quality, grayscale: grayscale) else { return 0 }

        if wholeFile { return Int64(data.count) }
        return Int64(Double(data.count) / Double(work.pageCount) * Double(pages.count))
    }

    /// Renders one page to JPEG and extrapolates. Pages are independent in this mode, so this holds up well.
    private func measureRendered(document: PDFDocument, pages: [Int], dpi: CGFloat, quality: Int, grayscale: Bool) -> Int64 {
        guard let page = document.page(at: pages[0]) else { return 0 }
        let sample = renderSamplePage(page: page, dpi: dpi, quality: quality, grayscale: grayscale)
        let overhead: Int64 = 10_000 + Int64(pages.count) * 2_000
        return sample * Int64(pages.count) + overhead
    }

    // MARK: - Private

    private func fileSize() -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? Int64) ?? 0
    }

    private func selectDPI(for targetPercentage: Int) -> CGFloat {
        let thresholds: [(Int, CGFloat)] = [(80, 150), (50, 120), (30, 100), (10, 72), (0, 50)]
        for (threshold, dpi) in thresholds {
            if targetPercentage >= threshold { return dpi }
        }
        return 50
    }

    private func renderSamplePage(page: PDFPage, dpi: CGFloat, quality: Int, grayscale: Bool) -> Int64 {
        let pageSize = page.displaySize
        let scale = dpi / 72.0
        let pixelWidth = Int(pageSize.width * scale)
        let pixelHeight = Int(pageSize.height * scale)

        let colorSpace: CGColorSpace = grayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let componentsPerPixel = grayscale ? 1 : 4
        let bytesPerRow = pixelWidth * componentsPerPixel
        let bitmapInfo: UInt32 = grayscale
            ? CGImageAlphaInfo.none.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return 0 }

        context.setFillColor(grayscale ? CGColor(gray: 1, alpha: 1) : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)

        guard let cgImage = context.makeImage() else { return 0 }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return 0 }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return 0 }

        return Int64(data.length)
    }
}
