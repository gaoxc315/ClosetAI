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

// MARK: - Press-drag tab bar (iOS 26 liquid-glass lens, same as 衣橱 / 穿搭 / 设置)

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
    @State private var isDragging = false
    @State private var hoverId: String?

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ZStack(alignment: .topLeading) {
                lens
                tabStack
            }
            .coordinateSpace(name: "magnifyTabs")
            .onPreferenceChange(TabItemFrameKey.self) { frames = $0 }
            .padding(4)
            .glassEffect(.regular, in: .rect(cornerRadius: axis == .horizontal ? 22 : 26))
            .gesture(dragGesture)
        }
        .sensoryFeedback(.selection, trigger: hoverId ?? selection)
    }

    @ViewBuilder
    private var lens: some View {
        if let rect = lensRect {
            Capsule()
                .fill(.clear)
                .frame(width: rect.width, height: rect.height)
                .glassEffect(.regular.interactive(), in: .capsule)
                .offset(x: rect.minX, y: rect.minY)
                .animation(
                    isDragging
                        ? .interactiveSpring(response: 0.16, dampingFraction: 0.9)
                        : .spring(response: 0.32, dampingFraction: 0.82),
                    value: rect
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var tabStack: some View {
        if axis == .horizontal {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    tabCell(item).frame(maxWidth: .infinity)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    tabCell(item).frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func tabCell(_ item: MagnifyingTabItem) -> some View {
        let selected = selection == item.id && !item.isAction
        return VStack(spacing: 3) {
            Image(systemName: item.icon)
                .font(.system(size: 22))
                .symbolVariant(selected ? .fill : .none)
                .symbolEffect(.bounce, value: selected)
            if !isDragging {
                Text(item.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .foregroundStyle(selected ? AppColors.accent : Color(.systemGray))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TabItemFrameKey.self,
                    value: [item.id: geo.frame(in: .named("magnifyTabs"))]
                )
            }
        )
        .onTapGesture { select(item, commitAction: true) }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("magnifyTabs"))
            .onChanged { value in
                let moved = hypot(value.translation.width, value.translation.height) > 6
                if moved, !isDragging {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isDragging = true
                    }
                }
                dragLocation = value.location
                if let item = item(at: value.location) {
                    hoverId = item.id
                    select(item, commitAction: false)
                }
            }
            .onEnded { value in
                if let item = item(at: value.location) ?? items.first(where: { $0.id == hoverId }) {
                    select(item, commitAction: true)
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    isDragging = false
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

    private func item(at point: CGPoint) -> MagnifyingTabItem? {
        if let hit = frames.first(where: { $0.value.insetBy(dx: -2, dy: -2).contains(point) })?.key {
            return items.first(where: { $0.id == hit })
        }
        return frames.min { a, b in
            let da = axis == .horizontal ? abs(a.value.midX - point.x) : abs(a.value.midY - point.y)
            let db = axis == .horizontal ? abs(b.value.midX - point.x) : abs(b.value.midY - point.y)
            return da < db
        }
        .flatMap { id, _ in items.first(where: { $0.id == id }) }
    }

    private var lensRect: CGRect? {
        if isDragging, let loc = dragLocation, let nearest = nearestFrame(to: loc) {
            if axis == .horizontal {
                let extra = min(abs(loc.x - nearest.midX) * 0.45, 22)
                let width = nearest.width + extra
                let height = max(nearest.height - 8, 36)
                return CGRect(x: loc.x - width / 2, y: nearest.minY + 4, width: width, height: height)
            } else {
                let extra = min(abs(loc.y - nearest.midY) * 0.45, 22)
                let height = nearest.height + extra
                let width = max(nearest.width - 8, 40)
                return CGRect(x: nearest.minX + 4, y: loc.y - height / 2, width: width, height: height)
            }
        }
        if let frame = frames[selection] {
            return frame.insetBy(dx: 3, dy: 4)
        }
        return nil
    }

    private func nearestFrame(to point: CGPoint) -> CGRect? {
        frames.min { a, b in
            let da = axis == .horizontal ? abs(a.value.midX - point.x) : abs(a.value.midY - point.y)
            let db = axis == .horizontal ? abs(b.value.midX - point.x) : abs(b.value.midY - point.y)
            return da < db
        }?.value
    }
}
