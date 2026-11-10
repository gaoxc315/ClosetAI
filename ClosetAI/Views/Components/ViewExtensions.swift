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
