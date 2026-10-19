import SwiftUI

struct OptionsView: View {
    @ObservedObject var appState: AppState
    @State private var removePages = false
    @State private var showPageSelector = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Options")
                .font(.system(size: 14, weight: .bold))

            // Mode
            Picker("Mode", selection: $appState.mode) {
                ForEach(CompressionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(appState.isCompressing)
            .onChange(of: appState.mode) { _ in
                appState.scheduleEstimate()
            }

            Text(appState.mode == .maximum && appState.hasTextLayer && appState.keepTextLayer
                 ? CompressionMode.maximumWithTextLayerDetail
                 : appState.mode.detail)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !appState.hasTextLayer {
                Text("This PDF has no text layer (probably a scan), so Maximum compression is preselected.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.mode == .maximum && appState.hasTextLayer {
                Toggle("Keep text selectable (invisible text layer)", isOn: $appState.keepTextLayer)
                    .font(.system(size: 13))
                    .disabled(appState.isCompressing)
                    .onChange(of: appState.keepTextLayer) { _ in
                        appState.scheduleEstimate()
                    }
            }

            // Grayscale toggle
            Toggle("Convert to grayscale (B&W)", isOn: $appState.grayscale)
                .font(.system(size: 13))
                .disabled(appState.isCompressing)
                .onChange(of: appState.grayscale) { _ in
                    appState.scheduleEstimate()
                }

            // Page removal
            HStack {
                Toggle("Remove specific pages", isOn: $removePages)
                    .font(.system(size: 13))
                    .disabled(appState.isCompressing)
                    .onChange(of: removePages) { newValue in
                        if !newValue {
                            appState.pagesToRemove = []
                            appState.scheduleEstimate()
                        } else if appState.pagesToRemove.isEmpty {
                            showPageSelector = true
                        }
                    }

                if removePages {
                    Button("Select...") {
                        showPageSelector = true
                    }
                    .font(.system(size: 12))
                    .disabled(appState.isCompressing)
                }
            }

            // Selection info
            if !appState.pagesToRemove.isEmpty {
                let pages = appState.pagesToRemove.sorted().map { $0 + 1 }
                let text = pages.count <= 5
                    ? "Selected: " + pages.map(String.init).joined(separator: ", ")
                    : "Selected: \(pages.count) pages"
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
        }
        .sheet(isPresented: $showPageSelector) {
            if let url = appState.currentPDFURL {
                PageSelectorView(
                    pdfURL: url,
                    pageCount: appState.pageCount,
                    selectedPages: $appState.pagesToRemove,
                    isPresented: $showPageSelector
                )
                .frame(minWidth: 500, minHeight: 400)
            }
        }
        .onChange(of: appState.pagesToRemove) { _ in
            appState.scheduleEstimate()
        }
    }
}
