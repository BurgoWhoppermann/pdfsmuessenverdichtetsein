import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Data Types

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
}

struct CompressionOptions {
    var targetPercentage: Int = 50
    var grayscale: Bool = false
    var pagesToRemove: Set<Int> = []
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

// MARK: - PDF Compressor

class PDFCompressionEngine {

    typealias ProgressCallback = (String, Int) -> Void

    private let inputURL: URL
    private let outputURL: URL
    private let options: CompressionOptions
    private let progressCallback: ProgressCallback

    init(inputURL: URL, outputURL: URL, options: CompressionOptions, progressCallback: @escaping ProgressCallback) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.options = options
        self.progressCallback = progressCallback
    }

    func compress() -> CompressionResult {
        let originalSize = fileSize(at: inputURL)

        progressCallback("Opening PDF...", 5)

        guard let sourceDocument = PDFDocument(url: inputURL) else {
            return CompressionResult(success: false, outputURL: nil, originalSize: originalSize, finalSize: 0, message: "Could not open PDF")
        }

        // Step 1: Remove pages if needed
        let workingDocument: PDFDocument
        if !options.pagesToRemove.isEmpty {
            workingDocument = removePages(from: sourceDocument, pages: options.pagesToRemove)
        } else {
            workingDocument = sourceDocument
        }

        let targetSize = Int64(Double(originalSize) * Double(options.targetPercentage) / 100.0)

        // Step 2: Compress with binary search for optimal JPEG quality
        progressCallback("Compressing images...", 10)
        let result = compressWithBinarySearch(document: workingDocument, targetSize: targetSize)

        if result {
            let finalSize = fileSize(at: outputURL)
            progressCallback("Done!", 100)
            return CompressionResult(success: true, outputURL: outputURL, originalSize: originalSize, finalSize: finalSize, message: "Compression successful")
        }

        // Step 3: Fallback — basic PDF re-save with Quartz filter
        progressCallback("Applying basic optimization...", 90)
        let fallbackResult = basicOptimization(document: workingDocument)

        if fallbackResult {
            let finalSize = fileSize(at: outputURL)
            progressCallback("Done!", 100)
            return CompressionResult(success: true, outputURL: outputURL, originalSize: originalSize, finalSize: finalSize, message: "Basic optimization applied")
        }

        return CompressionResult(success: false, outputURL: nil, originalSize: originalSize, finalSize: 0, message: "Compression failed")
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

    // MARK: - Binary Search Compression

    private func compressWithBinarySearch(document: PDFDocument, targetSize: Int64) -> Bool {
        let dpi = selectDPI(for: options.targetPercentage)
        var low = 5
        var high = 95
        var bestData: Data? = nil
        var bestSize: Int64 = 0
        var iterations = 0
        let maxIterations = 10

        progressCallback("Using DPI=\(Int(dpi)), searching for optimal quality...", 15)

        while low <= high && iterations < maxIterations {
            iterations += 1
            let mid = (low + high) / 2
            let progress = 15 + Int(Double(iterations) / Double(maxIterations) * 40)
            progressCallback("Trying quality=\(mid)%...", progress)

            if let pdfData = renderDocumentAsJPEG(document: document, dpi: dpi, quality: mid) {
                let currentSize = Int64(pdfData.count)

                // Within 5% tolerance
                let toleranceRatio = abs(Double(currentSize - targetSize)) / Double(targetSize)
                if toleranceRatio < 0.05 {
                    try? pdfData.write(to: outputURL)
                    return true
                }

                if currentSize <= targetSize {
                    if currentSize > bestSize {
                        bestData = pdfData
                        bestSize = currentSize
                    }
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            } else {
                high = mid - 1
            }
        }

        // Try lower DPI if nothing worked
        if bestData == nil && dpi > 50 {
            return compressWithLowerDPI(document: document, targetSize: targetSize, currentDPI: dpi)
        }

        if let data = bestData {
            try? data.write(to: outputURL)
            return true
        }

        return false
    }

    private func compressWithLowerDPI(document: PDFDocument, targetSize: Int64, currentDPI: CGFloat) -> Bool {
        let fallbackDPIs = dpiThresholds.map { $0.dpi }.filter { $0 < currentDPI }

        for dpi in fallbackDPIs {
            progressCallback("Trying lower DPI=\(Int(dpi))...", 55)
            var low = 5
            var high = 95
            var bestData: Data? = nil
            var bestSize: Int64 = 0

            while low <= high {
                let mid = (low + high) / 2
                if let pdfData = renderDocumentAsJPEG(document: document, dpi: dpi, quality: mid) {
                    let currentSize = Int64(pdfData.count)
                    if currentSize <= targetSize {
                        if currentSize > bestSize {
                            bestData = pdfData
                            bestSize = currentSize
                        }
                        low = mid + 1
                    } else {
                        high = mid - 1
                    }
                } else {
                    high = mid - 1
                }
            }

            if let data = bestData {
                try? data.write(to: outputURL)
                return true
            }
        }

        return false
    }

    // MARK: - Render PDF pages as JPEG images into a new PDF

    private func renderDocumentAsJPEG(document: PDFDocument, dpi: CGFloat, quality: Int) -> Data? {
        let mutableData = NSMutableData()

        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else { return nil }

        // We need to create the PDF context with the first page's box
        guard let firstPage = document.page(at: 0) else { return nil }
        let firstRect = firstPage.bounds(for: .mediaBox)
        var firstBox = CGRect(x: 0, y: 0, width: firstRect.width, height: firstRect.height)

        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else { return nil }

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let scale = dpi / 72.0
            let pixelWidth = Int(pageRect.width * scale)
            let pixelHeight = Int(pageRect.height * scale)

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
            page.draw(with: .mediaBox, to: bitmapContext)

            guard let cgImage = bitmapContext.makeImage() else { continue }

            // Compress to JPEG
            guard let jpegData = jpegData(from: cgImage, quality: quality) else { continue }

            // Decode JPEG back to CGImage
            guard let jpegSource = CGImageSourceCreateWithData(jpegData as CFData, nil),
                  let jpegImage = CGImageSourceCreateImageAtIndex(jpegSource, 0, nil) else { continue }

            // Begin PDF page
            var pageBox = CGRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height)
            pdfContext.beginPage(mediaBox: &pageBox)

            // Draw the JPEG image filling the page
            pdfContext.draw(jpegImage, in: pageBox)

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

    // MARK: - Basic Optimization (Quartz filter fallback)

    private func basicOptimization(document: PDFDocument) -> Bool {
        // Simple re-save — PDFKit will do basic cleanup
        return document.write(to: outputURL)
    }

    // MARK: - Utilities

    private func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}
