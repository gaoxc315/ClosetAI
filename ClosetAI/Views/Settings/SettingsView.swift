import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsVM = SettingsViewModel()
    @EnvironmentObject var wardrobeVM: WardrobeViewModel
    @EnvironmentObject var categoryStore: CategoryStore

    var body: some View {
        NavigationStack {
            List {
                statisticsSection
                categorySection
                dataSection
                infoSection
            }
            .font(.subheadline)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder private var statisticsSection: some View {
        Section {
            LabeledContent {
                Text("\(wardrobeVM.totalCount) 件")
                    .foregroundColor(.secondary)
            } label: {
                Label("衣物总数", systemImage: "tshirt")
            }

            NavigationLink(destination: ColorDistributionView(distribution: wardrobeVM.colorDistribution)) {
                Label("颜色分布", systemImage: "paintpalette")
            }

            NavigationLink(destination: NotWornRecentlyView(items: wardrobeVM.notWornRecently)) {
                LabeledContent {
                    Text("\(wardrobeVM.notWornRecently.count) 件")
                        .foregroundColor(wardrobeVM.notWornRecently.count > 5 ? .orange : .secondary)
                } label: {
                    Label("近90天未穿", systemImage: "clock")
                }
            }
        } header: {
            Text("统计面板")
        }
    }

    private var categorySection: some View {
        Section {
            NavigationLink {
                CategorySettingsView()
            } label: {
                LabeledContent {
                    Text("\(categoryStore.categories.count) 项")
                        .foregroundColor(.secondary)
                } label: {
                    Label("衣橱分类", systemImage: "square.grid.2x2")
                }
            }
            NavigationLink {
                ManageFamilyMembersView()
            } label: {
                LabeledContent {
                    Text("\(wardrobeVM.familyMembers.count) 人")
                        .foregroundColor(.secondary)
                } label: {
                    Label("家庭成员", systemImage: "person.2")
                }
            }
        } header: {
            Text("衣橱")
        } footer: {
            Text("分类显示在衣橱左侧；成员显示在顶部，可在此增删。")
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                settingsVM.showClearConfirm = true
            } label: {
                Label("清空已删除的衣物", systemImage: "trash")
            }
            .alert("确认清空", isPresented: $settingsVM.showClearConfirm) {
                Button("清空", role: .destructive) {
                    settingsVM.clearDeletedItems()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已软删除的衣物将被永久移除，此操作不可撤销。")
            }
        } header: {
            Text("数据管理")
        }
    }

    @ViewBuilder private var infoSection: some View {
        Section {
            LabeledContent {
                Text("1.0.0")
                    .foregroundColor(.secondary)
            } label: {
                Label("版本", systemImage: "info.circle")
            }

            LabeledContent {
                Text("iOS 26+")
                    .foregroundColor(.secondary)
            } label: {
                Label("平台", systemImage: "iphone")
            }
        } header: {
            Text("关于")
        }
    }
}

// MARK: - SettingsViewModel

class SettingsViewModel: ObservableObject {
    @Published var showClearConfirm = false

    func clearDeletedItems() {
        let items = PersistenceController.shared.fetchClothingItems(includeDeleted: true).filter { $0.isSoftDeleted }
        for item in items {
            if let path = item.originalImagePath {
                try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(path))
            }
            if let path = item.flatLayImagePath {
                try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(path))
            }
            PersistenceController.shared.deleteClothingItem(item, soft: false)
        }
    }
}

// MARK: - Color Distribution View

struct ColorDistributionView: View {
    let distribution: [String: Int]

    var sortedColors: [(String, Int)] {
        distribution.sorted { $0.value > $1.value }
    }

    var total: Int {
        distribution.values.reduce(0, +)
    }

    var body: some View {
        List {
            ForEach(sortedColors, id: \.0) { color, count in
                HStack {
                    Circle()
                        .fill(colorForName(color))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 0.5))
                    Text(color)
                    Spacer()
                    Text("\(count) 件")
                        .foregroundColor(.secondary)

                    // Progress bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.accent.opacity(0.3))
                        .frame(width: CGFloat(count) / CGFloat(max(total, 1)) * 80, height: 6)
                }
            }
        }
        .font(.subheadline)
        .navigationTitle("颜色分布")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func colorForName(_ name: String) -> Color {
        // 优先精确匹配，再通过关键词模糊匹配
        let n = name

        // 黑色系
        if n.contains("黑") { return .black }

        // 白色系（米白、象牙白、奶白、珍珠白 先于"白"匹配）
        if n.contains("米白") || n.contains("奶白") || n.contains("象牙") || n.contains("珍珠白") {
            return Color(red: 0.97, green: 0.94, blue: 0.88)
        }
        if n.contains("白") { return .white }

        // 米色 / 杏色 / 香槟 / 驼色 / 大地
        if n.contains("米") || n.contains("杏") || n.contains("香槟") || n.contains("驼") || n.contains("大地") {
            return Color(red: 0.91, green: 0.82, blue: 0.68)
        }

        // 卡其 / 沙色
        if n.contains("卡其") || n.contains("沙色") || n.contains("沙褐") {
            return Color(red: 0.76, green: 0.69, blue: 0.49)
        }

        // 灰色系（深灰/浅灰/银灰 先匹配）
        if n.contains("深灰") || n.contains("炭灰") { return Color(red: 0.3, green: 0.3, blue: 0.3) }
        if n.contains("浅灰") || n.contains("银灰") || n.contains("麻灰") { return Color(red: 0.78, green: 0.78, blue: 0.78) }
        if n.contains("灰") { return .gray }

        // 红色系（酒红/深红/玫红/枣红 先匹配）
        if n.contains("酒红") || n.contains("深红") || n.contains("枣红") || n.contains("勃艮第") {
            return Color(red: 0.55, green: 0.1, blue: 0.2)
        }
        if n.contains("玫") || n.contains("粉红") { return Color(red: 1.0, green: 0.4, blue: 0.6) }
        if n.contains("红") { return .red }

        // 蓝色系（藏蓝/深蓝/海军蓝 先匹配）
        if n.contains("藏蓝") || n.contains("深蓝") || n.contains("海军") || n.contains("宝蓝") {
            return Color(red: 0.05, green: 0.1, blue: 0.45)
        }
        if n.contains("浅蓝") || n.contains("天蓝") || n.contains("牛仔") { return Color(red: 0.43, green: 0.65, blue: 0.88) }
        if n.contains("蓝") { return .blue }

        // 绿色系（军绿/墨绿/橄榄绿 先匹配）
        if n.contains("军绿") || n.contains("墨绿") || n.contains("橄榄") || n.contains("深绿") {
            return Color(red: 0.2, green: 0.35, blue: 0.18)
        }
        if n.contains("浅绿") || n.contains("薄荷") { return Color(red: 0.6, green: 0.87, blue: 0.72) }
        if n.contains("绿") { return .green }

        // 黄色系
        if n.contains("姜黄") || n.contains("芥黄") { return Color(red: 0.79, green: 0.66, blue: 0.2) }
        if n.contains("黄") { return .yellow }

        // 橙色系
        if n.contains("橙") || n.contains("南瓜") { return .orange }
        if n.contains("珊瑚") || n.contains("砖红") { return Color(red: 0.91, green: 0.45, blue: 0.35) }

        // 粉色系（薰衣草、淡紫 先匹配）
        if n.contains("薰衣草") || n.contains("淡紫") { return Color(red: 0.73, green: 0.67, blue: 0.90) }
        if n.contains("粉") { return .pink }

        // 紫色系
        if n.contains("紫") { return .purple }

        // 棕色系（咖色、焦糖、巧克力）
        if n.contains("棕") || n.contains("咖") || n.contains("焦糖") || n.contains("巧克力") || n.contains("褐") {
            return .brown
        }

        // 金属色
        if n.contains("金") { return Color(red: 0.85, green: 0.72, blue: 0.35) }
        if n.contains("银") { return Color(red: 0.75, green: 0.75, blue: 0.78) }

        return Color(.systemGray3)
    }
}

// MARK: - Not Worn Recently View

struct NotWornRecentlyView: View {
    let items: [ClothingItem]
    @EnvironmentObject var wardrobeVM: WardrobeViewModel

    var body: some View {
        List {
            if items.isEmpty {
                Text("近 90 天内所有衣物都有穿着记录")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.subCategory ?? item.category ?? "未知")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(wardrobeVM.lastOutfitDate(for: item).map { "上次穿着: \(formatDate($0))" } ?? "从未加入穿搭")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .font(.subheadline)
        .navigationTitle("近90天未穿")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}

// MARK: - Category settings

struct CategorySettingsView: View {
    @EnvironmentObject var categoryStore: CategoryStore
    @State private var editor: CategoryEditorState?

    var body: some View {
        List {
            Section {
                ForEach(categoryStore.categories) { category in
                    Button {
                        editor = CategoryEditorState(category: category)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.icon)
                                .font(.body)
                                .foregroundStyle(AppColors.accent)
                                .frame(width: 28)
                            Text(category.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onMove(perform: categoryStore.move)
                .onDelete(perform: categoryStore.delete)
            } footer: {
                Text("「全部」始终在衣橱左侧顶部。删除分类不会删除衣物。")
            }
        }
        .font(.subheadline)
        .navigationTitle("衣橱分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editor = CategoryEditorState()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editor) { state in
            CategoryEditorSheet(state: state) { name, icon in
                if let category = state.category {
                    return categoryStore.update(category, name: name, icon: icon)
                }
                return categoryStore.add(name: name, icon: icon)
            }
        }
    }
}

private struct CategoryEditorState: Identifiable {
    let id = UUID()
    var category: WardrobeCategory?
    var name: String
    var icon: String

    init(category: WardrobeCategory? = nil) {
        self.category = category
        self.name = category?.name ?? ""
        self.icon = category?.icon ?? "tshirt"
    }
}

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: CategoryEditorState
    var onSave: (String, String) -> String?

    @State private var name: String
    @State private var icon: String
    @State private var errorMessage: String?

    init(state: CategoryEditorState, onSave: @escaping (String, String) -> String?) {
        self.state = state
        self.onSave = onSave
        _name = State(initialValue: state.name)
        _icon = State(initialValue: state.icon)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 44), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如：帽子", text: $name)
                }
                Section("图标") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(CategoryStore.iconChoices, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(icon == symbol ? .white : AppColors.accent)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(icon == symbol ? AppColors.accent : Color(.systemGray6))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(state.category == nil ? "添加分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let error = onSave(name, icon) {
                            errorMessage = error
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }
}
