import Foundation
import SwiftUI
import PDFKit
import Combine

/// Central app state — drives the entire UI.
@MainActor
class AppState: ObservableObject {

    // MARK: - Published State

    @Published var currentPDFURL: URL? = nil
    @Published var fileName: String = ""
    @Published var fileSizeMB: Double = 0

    @Published var targetPercentage: Int = 50
    @Published var grayscale: Bool = false
    @Published var pagesToRemove: Set<Int> = []
    @Published var pageCount: Int = 0

    @Published var isCompressing: Bool = false
    @Published var progressMessage: String = ""
    @Published var progressValue: Double = 0

    @Published var estimatedSizeBytes: Int64? = nil
    @Published var isEstimating: Bool = false

    @Published var compressionResult: CompressionResult? = nil
    @Published var outputURL: URL? = nil

    // MARK: - Private

    private var estimateTask: Task<Void, Never>? = nil

    // MARK: - File Loading

    func loadPDF(url: URL) {
        guard let document = PDFDocument(url: url) else { return }

        currentPDFURL = url
        fileName = url.lastPathComponent
        fileSizeMB = Double(fileSize(at: url)) / (1024.0 * 1024.0)
        pageCount = document.pageCount
        pagesToRemove = []
        compressionResult = nil
        outputURL = nil
        progressMessage = "Ready to compress"
        progressValue = 0

        scheduleEstimate()
    }

    // MARK: - Estimation

    func scheduleEstimate() {
        estimateTask?.cancel()
        guard currentPDFURL != nil else { return }

        isEstimating = true
        estimatedSizeBytes = nil

        let url = currentPDFURL!
        let target = targetPercentage
        let gray = grayscale
        let removedPages = pagesToRemove

        estimateTask = Task {
            // Debounce 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let result = await Task.detached(priority: .userInitiated) {
                let estimator = PreviewEstimator(url: url)
                return estimator.estimateSize(
                    targetPercentage: target,
                    grayscale: gray,
                    pagesToRemove: removedPages
                )
            }.value

            guard !Task.isCancelled else { return }

            self.estimatedSizeBytes = result
            self.isEstimating = false
        }
    }

    // MARK: - Compression

    func compress(to outputURL: URL) {
        guard let inputURL = currentPDFURL else { return }

        isCompressing = true
        compressionResult = nil
        self.outputURL = outputURL
        progressValue = 0

        let options = CompressionOptions(
            targetPercentage: targetPercentage,
            grayscale: grayscale,
            pagesToRemove: pagesToRemove
        )

        Task.detached(priority: .userInitiated) { [weak self] in
            let engine = PDFCompressionEngine(
                inputURL: inputURL,
                outputURL: outputURL,
                options: options,
                progressCallback: { message, percent in
                    Task { @MainActor in
                        self?.progressMessage = message
                        self?.progressValue = Double(percent) / 100.0
                    }
                }
            )

            let result = engine.compress()

            let finalResult = result
            await MainActor.run { [weak self] in
                self?.compressionResult = finalResult
                self?.isCompressing = false
            }
        }
    }

    // MARK: - Helpers

    func reset() {
        currentPDFURL = nil
        fileName = ""
        fileSizeMB = 0
        targetPercentage = 50
        grayscale = false
        pagesToRemove = []
        pageCount = 0
        isCompressing = false
        progressMessage = ""
        progressValue = 0
        estimatedSizeBytes = nil
        compressionResult = nil
        outputURL = nil
    }

    var estimateColor: Color {
        guard let estimated = estimatedSizeBytes, fileSizeMB > 0 else { return .secondary }
        let estimatedMB = Double(estimated) / (1024.0 * 1024.0)
        let targetMB = fileSizeMB * Double(targetPercentage) / 100.0

        if estimatedMB <= targetMB * 0.95 { return .green }
        if estimatedMB <= targetMB * 1.05 { return .orange }
        return .red
    }

    private func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}
