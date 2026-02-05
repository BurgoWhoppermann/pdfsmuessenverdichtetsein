import SwiftUI

struct CompressButton: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button(action: startCompression) {
            Text(appState.isCompressing ? "Compressing..." : "Compress PDF")
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 45)
        }
        .buttonStyle(.borderedProminent)
        .disabled(appState.currentPDFURL == nil || appState.isCompressing)
    }

    private func startCompression() {
        guard let inputURL = appState.currentPDFURL else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_compressed.pdf"
        panel.directoryURL = inputURL.deletingLastPathComponent()

        if panel.runModal() == .OK, let outputURL = panel.url {
            appState.compress(to: outputURL)
        }
    }
}
