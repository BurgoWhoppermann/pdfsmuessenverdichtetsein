import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Estimates compressed file size by sampling a single page and extrapolating.
class PreviewEstimator {

    private let pdfURL: URL

    init(url: URL) {
        self.pdfURL = url
    }

    /// Estimate compressed size in bytes.
    func estimateSize(targetPercentage: Int, grayscale: Bool, pagesToRemove: Set<Int>) -> Int64 {
        guard let document = PDFDocument(url: pdfURL) else { return 0 }

        let totalPages = document.pageCount
        let remainingPages = totalPages - pagesToRemove.count

        guard remainingPages > 0 else { return 0 }

        // Find first non-removed page
        var samplePageIndex = 0
        for i in 0..<totalPages {
            if !pagesToRemove.contains(i) {
                samplePageIndex = i
                break
            }
        }

        guard let page = document.page(at: samplePageIndex) else { return 0 }

        let sampleSize = compressSamplePage(page: page, targetPercentage: targetPercentage, grayscale: grayscale)

        // Extrapolate + overhead
        let pdfOverhead: Int64 = 10_000 + Int64(remainingPages) * 2_000
        let estimated = Int64(sampleSize) * Int64(remainingPages) + pdfOverhead

        return estimated
    }

    // MARK: - Private

    private func selectDPI(for targetPercentage: Int) -> CGFloat {
        let thresholds: [(Int, CGFloat)] = [(80, 150), (50, 120), (30, 100), (10, 72), (0, 50)]
        for (threshold, dpi) in thresholds {
            if targetPercentage >= threshold { return dpi }
        }
        return 50
    }

    private func selectQuality(for targetPercentage: Int) -> Int {
        if targetPercentage >= 80 { return 85 }
        if targetPercentage >= 60 { return 70 }
        if targetPercentage >= 40 { return 55 }
        if targetPercentage >= 25 { return 40 }
        return 25
    }

    private func compressSamplePage(page: PDFPage, targetPercentage: Int, grayscale: Bool) -> Int64 {
        let dpi = selectDPI(for: targetPercentage)
        let quality = selectQuality(for: targetPercentage)

        let pageRect = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let pixelWidth = Int(pageRect.width * scale)
        let pixelHeight = Int(pageRect.height * scale)

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
        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else { return 0 }

        // Compress to JPEG
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
