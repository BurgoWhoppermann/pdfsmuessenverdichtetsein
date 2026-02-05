import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @ObservedObject var appState: AppState
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: appState.currentPDFURL == nil ? [8, 4] : [])
                        )
                        .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.4))
                )

            if let _ = appState.currentPDFURL {
                // File loaded state
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)

                    Text(appState.fileName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(String(format: "%.2f MB", appState.fileSizeMB))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Text("Click to change file")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("Drop PDF here")
                        .font(.system(size: 18, weight: .bold))

                    Text("or click to browse")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .frame(height: 180)
        .onTapGesture {
            openFilePicker()
        }
        .onDrop(of: [.pdf, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.loadPDF(url: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // Try PDF type first
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, error in
                    if let url = item as? URL {
                        Task { @MainActor in
                            appState.loadPDF(url: url)
                        }
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task { @MainActor in
                            appState.loadPDF(url: url)
                        }
                    }
                }
                return
            }
            // Try file URL
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       url.pathExtension.lowercased() == "pdf" {
                        Task { @MainActor in
                            appState.loadPDF(url: url)
                        }
                    }
                }
                return
            }
        }
    }
}
