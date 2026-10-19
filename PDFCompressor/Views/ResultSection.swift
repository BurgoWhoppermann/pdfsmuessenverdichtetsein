import SwiftUI

struct ResultSection: View {
    let result: CompressionResult
    let outputURL: URL?
    var onSwitchToMaximum: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            if result.success {
                let originalMB = Double(result.originalSize) / (1024.0 * 1024.0)
                let finalMB = Double(result.finalSize) / (1024.0 * 1024.0)
                let reduction = 100 - result.compressionRatio

                Text(String(format: "Compressed: %.2f MB \u{2192} %.2f MB (%.1f%% reduction)", originalMB, finalMB, reduction))
                    .font(.system(size: 13))
                    .foregroundColor(result.targetReached ? .green : .orange)

                if !result.targetReached {
                    missedTargetHint
                }

                if let url = outputURL {
                    Button("Open Output Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            } else {
                Text(result.message)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var missedTargetHint: some View {
        if result.mode == .keepText {
            Text("Keep text could not reach the target size. The images are already at the lowest setting, the rest of the file is text and vector data. Maximum compression turns every page into a picture, which can go smaller but removes selectable text, and for text or vector PDFs it can even make the file bigger.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let onSwitchToMaximum {
                Button("Switch to Maximum compression", action: onSwitchToMaximum)
            }
        } else {
            Text("The target size could not be reached. This is the smallest result at the lowest quality.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}
