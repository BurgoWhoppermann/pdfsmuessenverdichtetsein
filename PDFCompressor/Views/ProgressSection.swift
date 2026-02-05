import SwiftUI

struct ProgressSection: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: appState.progressValue)
                .progressViewStyle(.linear)

            Text(appState.progressMessage)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}
