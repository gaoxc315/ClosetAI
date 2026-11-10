import SwiftUI

struct LocalImageView: View {
    let path: String?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(Color(.systemGray3))
                            .font(.system(size: 24))
                    )
            }
        }
        .onAppear { loadImage() }
        .onChange(of: path) { _, _ in loadImage() }
    }

    private func loadImage() {
        guard let path = path, !path.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let img = UIImage(contentsOfFile: Self.resolvePath(path))
            DispatchQueue.main.async { self.image = img }
        }
    }

    /// 兼容两种存储格式：
    /// 1. 旧版绝对路径（每次重装/更新后沙箱 UUID 变化导致失效）
    /// 2. 新版只存文件名（每次动态拼接当前 Documents 路径）
    static func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") && FileManager.default.fileExists(atPath: path) {
            return path
        }
        let filename = path.hasPrefix("/") ? (path as NSString).lastPathComponent : path
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(filename).path
    }
}

// MARK: - Pinch-zoom image (pan when zoomed, double-tap toggle)

struct ZoomableImageView: View {
    let path: String?
    var contentMode: ContentMode = .fit
    @Binding var scale: CGFloat

    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 6

    var body: some View {
        LocalImageView(path: path, contentMode: contentMode)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnifyGesture)
            .simultaneousGesture(panGesture)
            .onTapGesture(count: 2, perform: toggleZoom)
            .onChange(of: path) { _, _ in reset() }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let next = lastScale * value.magnification
                scale = min(max(next, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale + 0.02 {
                    reset()
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale + 0.02 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if scale > 1.2 {
                reset()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

struct FullscreenImageViewer: View {
    let path: String?
    var title: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ZoomableImageView(path: path, contentMode: .fit, scale: $scale)
                    .ignoresSafeArea()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Clothing Item Card (square cell; image never drives layout width)

struct ClothingItemCard: View {
    let item: ClothingItem
    var isIdle: Bool = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack(alignment: .topTrailing) {
                    LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if isIdle {
                        Text("未搭配")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(AppColors.idle)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}
