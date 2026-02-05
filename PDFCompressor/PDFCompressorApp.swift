import SwiftUI

@main
struct PDFCompressorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 420, height: 650)
    }
}
