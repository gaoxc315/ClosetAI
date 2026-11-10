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
