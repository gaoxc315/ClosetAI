import SwiftUI

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
            .frame(minWidth: 56, maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: - Press-drag tab bar (same interaction as 衣橱 / 穿搭 / 设置)

struct MagnifyingTabItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    var isAction: Bool = false
}

private struct TabItemFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct MagnifyingTabBar: View {
    let items: [MagnifyingTabItem]
    var axis: Axis = .horizontal
    @Binding var selection: String
    var onSelect: (MagnifyingTabItem) -> Void

    @State private var frames: [String: CGRect] = [:]
    @State private var dragLocation: CGPoint?
    @State private var hoverId: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            tabStack
                .coordinateSpace(name: "magnifyTabs")
                .onPreferenceChange(TabItemFrameKey.self) { frames = $0 }
                .gesture(dragGesture)
                .sensoryFeedback(.selection, trigger: hoverId)

            if let dragLocation, let hover = hoveringItem {
                loupe(for: hover)
                    .position(loupePosition(at: dragLocation))
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var tabStack: some View {
        if axis == .horizontal {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    tabCell(item)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    tabCell(item)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func tabCell(_ item: MagnifyingTabItem) -> some View {
        let selected = selection == item.id && !item.isAction
        let scale = magnification(for: item.id)
        return VStack(spacing: 3) {
            Image(systemName: item.icon)
                .font(.system(size: 22))
                .symbolVariant(selected ? .fill : .none)
            Text(item.title)
                .font(.system(size: 10))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(selected ? AppColors.accent : Color(.systemGray))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .scaleEffect(scale, anchor: .center)
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TabItemFrameKey.self,
                    value: [item.id: geo.frame(in: .named("magnifyTabs"))]
                )
            }
        )
        .onTapGesture {
            select(item, commitAction: true)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("magnifyTabs"))
            .onChanged { value in
                dragLocation = value.location
                if let item = item(at: value.location) {
                    hoverId = item.id
                    select(item, commitAction: false)
                }
            }
            .onEnded { value in
                if let item = item(at: value.location) ?? hoveringItem {
                    select(item, commitAction: true)
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    dragLocation = nil
                    hoverId = nil
                }
            }
    }

    private func select(_ item: MagnifyingTabItem, commitAction: Bool) {
        if item.isAction {
            if commitAction { onSelect(item) }
            return
        }
        if selection != item.id {
            selection = item.id
            onSelect(item)
        }
    }

    private var hoveringItem: MagnifyingTabItem? {
        items.first(where: { $0.id == hoverId })
    }

    private func item(at point: CGPoint) -> MagnifyingTabItem? {
        let hit = frames.first { $0.value.insetBy(dx: -4, dy: -4).contains(point) }?.key
        if let hit { return items.first(where: { $0.id == hit }) }
        return nearestItem(to: point)
    }

    private func nearestItem(to point: CGPoint) -> MagnifyingTabItem? {
        frames.min { a, b in
            let da = axis == .horizontal ? abs(a.value.midX - point.x) : abs(a.value.midY - point.y)
            let db = axis == .horizontal ? abs(b.value.midX - point.x) : abs(b.value.midY - point.y)
            return da < db
        }
        .flatMap { id, _ in items.first(where: { $0.id == id }) }
    }

    private func magnification(for id: String) -> CGFloat {
        guard let dragLocation, let frame = frames[id] else { return 1 }
        let delta = axis == .horizontal
            ? abs(frame.midX - dragLocation.x)
            : abs(frame.midY - dragLocation.y)
        let sigma: CGFloat = 42
        let influence = exp(-0.5 * pow(delta / sigma, 2))
        return 1 + 0.55 * influence
    }

    private func loupePosition(at location: CGPoint) -> CGPoint {
        if axis == .horizontal {
            return CGPoint(x: location.x, y: location.y + 70)
        }
        return CGPoint(x: location.x + 64, y: location.y)
    }

    private func loupe(for item: MagnifyingTabItem) -> some View {
        VStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.system(size: 36, weight: .regular))
                .symbolVariant(.fill)
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(AppColors.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }
}
