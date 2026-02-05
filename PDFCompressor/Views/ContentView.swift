import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Title
                Text("PDFs verdichten")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 4)

                // Drop Zone
                DropZoneView(appState: appState)

                // Size Slider
                if appState.currentPDFURL != nil {
                    SizeSliderView(appState: appState)

                    // Options
                    OptionsView(appState: appState)

                    // Compress Button
                    CompressButton(appState: appState)

                    // Progress
                    if appState.isCompressing {
                        ProgressSection(appState: appState)
                    }

                    // Result
                    if let result = appState.compressionResult, result.success {
                        ResultSection(result: result, outputURL: appState.outputURL)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
