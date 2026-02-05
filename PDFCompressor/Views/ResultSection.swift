import SwiftUI

struct ResultSection: View {
    let result: CompressionResult
    let outputURL: URL?

    var body: some View {
        VStack(spacing: 10) {
            let originalMB = Double(result.originalSize) / (1024.0 * 1024.0)
            let finalMB = Double(result.finalSize) / (1024.0 * 1024.0)
            let reduction = 100 - result.compressionRatio

            Text(String(format: "Compressed: %.2f MB \u{2192} %.2f MB (%.1f%% reduction)", originalMB, finalMB, reduction))
                .font(.system(size: 13))
                .foregroundColor(.green)

            if let url = outputURL {
                Button("Open Output Folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        .padding(.top, 8)
    }
}
