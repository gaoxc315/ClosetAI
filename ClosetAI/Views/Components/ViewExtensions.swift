import SwiftUI
import UIKit

// MARK: - Keyboard Dismiss Helper

extension UIApplication {
    static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

// MARK: - Error Toast Modifier

/// 在视图底部以红色 Capsule 弹出错误消息，3.5 秒后自动消失，点击可手动关闭。
/// 用法：.errorToast($viewModel.errorMessage)
struct ErrorToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let msg = message {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                    Text(msg)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(
                    Capsule()
                        .fill(Color(red: 0.85, green: 0.2, blue: 0.2).opacity(0.92))
                        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture {
                    withAnimation { message = nil }
                }
                .onAppear {
                    let captured = msg
                    Task {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        // 只有消息未被手动清除时才自动关闭
                        if message == captured {
                            withAnimation { message = nil }
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: message)
    }
}

extension View {
    func errorToast(_ message: Binding<String?>) -> some View {
        modifier(ErrorToastModifier(message: message))
    }
}

// MARK: - Tab-style item (matches 衣橱 / 穿搭 / 设置)

struct AppTabItem: View {
    let icon: String
    let title: String
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                action()
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .symbolVariant(selected ? .fill : .none)
                Text(title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? AppColors.accent : Color(.systemGray))
            .frame(minWidth: 56, maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum AppTabIcon {
    static func category(_ name: String) -> String {
        switch name {
        case "全部": return "square.grid.2x2"
        case "上装": return "tshirt"
        case "外套": return "jacket"
        case "连衣裙": return "figure.stand.dress"
        case "下装": return "rectangle.split.1x2"
        case "鞋子": return "shoe"
        case "包包": return "bag"
        case "配饰": return "sparkle"
        default: return "ellipsis.circle"
        }
    }
}

// MARK: - System tab bar (real UITabBar = same liquid-glass lens as 衣橱 / 穿搭 / 设置)

struct MagnifyingTabItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    var isAction: Bool = false
}

struct MagnifyingTabBar: View {
    let items: [MagnifyingTabItem]
    @Binding var selection: String
    var onSelect: (MagnifyingTabItem) -> Void

    var body: some View {
        SystemTabBar(items: items, selection: $selection, onSelect: onSelect)
            // Lens overflows the bar by a few points, same as the root tab bar.
            .padding(.vertical, 10)
    }
}

private struct SystemTabBar: UIViewRepresentable {
    var items: [MagnifyingTabItem]
    @Binding var selection: String
    var onSelect: (MagnifyingTabItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SystemTabBarView {
        let view = SystemTabBarView()
        view.tabBar.delegate = context.coordinator
        view.tabBar.tintColor = UIColor(AppColors.accent)
        view.tabBar.unselectedItemTintColor = .systemGray
        view.tabBar.isTranslucent = true
        view.tabBar.backgroundColor = .clear
        context.coordinator.onSelect = { item, bar in
            handleSelect(item, bar: bar)
        }
        context.coordinator.sync(view.tabBar, items: items, selection: selection)
        view.itemCount = items.count
        return view
    }

    func updateUIView(_ view: SystemTabBarView, context: Context) {
        context.coordinator.onSelect = { item, bar in
            handleSelect(item, bar: bar)
        }
        context.coordinator.sync(view.tabBar, items: items, selection: selection)
        view.itemCount = items.count
        view.setNeedsLayout()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SystemTabBarView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let fitting = uiView.tabBar.sizeThatFits(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        )
        return CGSize(width: width, height: max(fitting.height, 49))
    }

    private func handleSelect(_ item: MagnifyingTabItem, bar: UITabBar) {
        if item.isAction {
            restoreSelection(on: bar)
            onSelect(item)
            return
        }
        if selection != item.id {
            selection = item.id
            onSelect(item)
        }
    }

    private func restoreSelection(on bar: UITabBar) {
        guard let index = items.firstIndex(where: { $0.id == selection }),
              let uiItems = bar.items,
              uiItems.indices.contains(index)
        else { return }
        bar.selectedItem = uiItems[index]
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var itemIDs: [String] = []
        var items: [MagnifyingTabItem] = []
        var onSelect: ((MagnifyingTabItem, UITabBar) -> Void)?

        func sync(_ bar: UITabBar, items: [MagnifyingTabItem], selection: String) {
            self.items = items
            let ids = items.map(\.id)
            if ids != itemIDs {
                bar.items = items.enumerated().map { index, item in
                    let uiItem = UITabBarItem(
                        title: item.title,
                        image: UIImage(systemName: item.icon),
                        selectedImage: UIImage(systemName: item.icon)
                    )
                    uiItem.tag = index
                    return uiItem
                }
                itemIDs = ids
            }
            if let index = items.firstIndex(where: { $0.id == selection && !$0.isAction }),
               let uiItems = bar.items,
               uiItems.indices.contains(index) {
                bar.selectedItem = uiItems[index]
            }
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            let index = item.tag
            guard items.indices.contains(index) else { return }
            onSelect?(items[index], tabBar)
        }
    }
}

final class SystemTabBarView: UIView {
    let tabBar = UITabBar()
    let scrollView = UIScrollView()
    var itemCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
        scrollView.backgroundColor = .clear
        scrollView.clipsToBounds = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        tabBar.clipsToBounds = false
        addSubview(scrollView)
        scrollView.addSubview(tabBar)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        let needed = CGFloat(max(itemCount, 1)) * 64
        let width = max(bounds.width, needed)
        tabBar.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        scrollView.contentSize = CGSize(width: width, height: bounds.height)
        scrollView.isScrollEnabled = needed > bounds.width + 1
    }
}
