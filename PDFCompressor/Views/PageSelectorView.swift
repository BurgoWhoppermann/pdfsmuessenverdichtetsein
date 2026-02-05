import SwiftUI
import PDFKit

struct PageSelectorView: View {
    let pdfURL: URL
    let pageCount: Int
    @Binding var selectedPages: Set<Int>
    @Binding var isPresented: Bool

    @State private var localSelection: Set<Int> = []
    @State private var thumbnails: [Int: NSImage] = [:]
    @State private var isLoading = true

    private let columns = [
        GridItem(.adaptive(minimum: 130), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Click pages to select for removal")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(localSelection.count) selected")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)

            // Thumbnails grid
            ScrollView {
                if isLoading {
                    ProgressView("Loading thumbnails...")
                        .padding(50)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(0..<pageCount, id: \.self) { pageIndex in
                            PageThumbnailView(
                                pageIndex: pageIndex,
                                image: thumbnails[pageIndex],
                                isSelected: localSelection.contains(pageIndex),
                                onTap: {
                                    if localSelection.contains(pageIndex) {
                                        localSelection.remove(pageIndex)
                                    } else {
                                        localSelection.insert(pageIndex)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }

            // Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Button("Select All") {
                    localSelection = Set(0..<pageCount)
                }

                Button("Clear All") {
                    localSelection = []
                }

                Spacer()

                Button("Confirm") {
                    selectedPages = localSelection
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .onAppear {
            localSelection = selectedPages
            loadThumbnails()
        }
    }

    private func loadThumbnails() {
        Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: pdfURL) else {
                await MainActor.run { isLoading = false }
                return
            }

            var thumbs: [Int: NSImage] = [:]

            for i in 0..<document.pageCount {
                guard let page = document.page(at: i) else { continue }

                let pageRect = page.bounds(for: .mediaBox)
                let maxDim: CGFloat = 120
                let scale = maxDim / max(pageRect.width, pageRect.height)

                let thumbWidth = pageRect.width * scale
                let thumbHeight = pageRect.height * scale

                let image = NSImage(size: NSSize(width: thumbWidth, height: thumbHeight))
                image.lockFocus()

                if let context = NSGraphicsContext.current?.cgContext {
                    context.setFillColor(NSColor.white.cgColor)
                    context.fill(CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))
                    context.scaleBy(x: scale, y: scale)
                    page.draw(with: .mediaBox, to: context)
                }

                image.unlockFocus()
                thumbs[i] = image
            }

            let result = thumbs
            await MainActor.run {
                thumbnails = result
                isLoading = false
            }
        }
    }
}

// MARK: - Single Thumbnail

struct PageThumbnailView: View {
    let pageIndex: Int
    let image: NSImage?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 160)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 120, height: 160)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text("Page \(pageIndex + 1)")
                .font(.system(size: 11))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture { onTap() }
    }
}
