import SwiftUI

struct SizeSliderView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Size")
                .font(.system(size: 14, weight: .bold))

            // Slider with labels
            HStack {
                Text("10%")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(appState.targetPercentage) },
                        set: { newVal in
                            appState.targetPercentage = Int(newVal)
                            appState.scheduleEstimate()
                        }
                    ),
                    in: 10...100,
                    step: 1
                )

                Text("100%")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Target value
            Text("Target: \(appState.targetPercentage)%")
                .font(.system(size: 13))

            // Estimated result
            estimateView
        }
    }

    @ViewBuilder
    private var estimateView: some View {
        if appState.isEstimating {
            Text("Estimated result: calculating...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        } else if let estimated = appState.estimatedSizeBytes {
            let estimatedMB = Double(estimated) / (1024.0 * 1024.0)
            Text(String(format: "Estimated result: ~%.2f MB", estimatedMB))
                .font(.system(size: 12))
                .foregroundColor(appState.estimateColor)

            if appState.keepTextMissesTarget {
                Text(appState.hasTextLayer && appState.keepTextLayer
                     ? "With Keep text this PDF will probably stay above the target. Maximum compression can reach it and still keep the text selectable."
                     : "With Keep text this PDF will probably stay above the target. Its images cannot be shrunk much without turning pages into pictures.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Switch to Maximum compression") {
                    appState.mode = .maximum
                    appState.scheduleEstimate()
                }
                .font(.system(size: 12))
                .disabled(appState.isCompressing)
            }
        }
    }
}
