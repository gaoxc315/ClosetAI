import Foundation
import SwiftUI
import Combine

struct WardrobeCategory: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var icon: String

    init(id: UUID = UUID(), name: String, icon: String) {
        self.id = id
        self.name = name
        self.icon = icon
    }
}

final class CategoryStore: ObservableObject {
    static let allCategoryName = "全部"

    static let defaultCategories: [WardrobeCategory] = [
        WardrobeCategory(name: "上装", icon: "tshirt"),
        WardrobeCategory(name: "外套", icon: "jacket"),
        WardrobeCategory(name: "连衣裙", icon: "figure.stand.dress"),
        WardrobeCategory(name: "下装", icon: "rectangle.split.1x2"),
        WardrobeCategory(name: "鞋子", icon: "shoe"),
        WardrobeCategory(name: "包包", icon: "bag"),
        WardrobeCategory(name: "配饰", icon: "sparkle"),
        WardrobeCategory(name: "其他", icon: "ellipsis.circle"),
    ]

    static let iconChoices = [
        "tshirt", "jacket", "figure.stand.dress", "rectangle.split.1x2",
        "shoe", "bag", "sparkle", "hat.widebrim", "eyeglasses",
        "watch.classic", "comb", "umbrella", "snowflake", "sun.max",
        "hanger", "shippingbox", "star", "heart", "ellipsis.circle",
    ]

    private static let defaultsKey = "closetai.wardrobeCategories"

    @Published var categories: [WardrobeCategory] {
        didSet {
            guard !isApplyingRemote, isBootstrapped else { return }
            persist()
        }
    }

    var names: [String] {
        categories.map(\.name)
    }

    private var isApplyingRemote = false
    private var isBootstrapped = false
    private var cloudObserver: NSObjectProtocol?

    init() {
        if let legacy = Self.loadFromUserDefaults() {
            categories = legacy
        } else {
            categories = Self.defaultCategories
        }

        DispatchQueue.main.async { [weak self] in
            self?.bootstrapFromPersistence()
        }

        cloudObserver = NotificationCenter.default.addObserver(
            forName: .closetAICloudDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFromCloud()
        }
    }

    deinit {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
    }

    func add(name: String, icon: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validate(name: trimmed, ignoring: nil) {
            return error
        }
        categories.append(WardrobeCategory(name: trimmed, icon: icon))
        return nil
    }

    func update(_ category: WardrobeCategory, name: String, icon: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validate(name: trimmed, ignoring: category.id) {
            return error
        }
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return "分类不存在" }
        let oldName = categories[index].name
        categories[index].name = trimmed
        categories[index].icon = icon
        if oldName != trimmed {
            remapItems(from: oldName, to: trimmed)
        }
        return nil
    }

    func delete(at offsets: IndexSet) {
        categories.remove(atOffsets: offsets)
    }

    func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
    }

    func icon(forName name: String) -> String {
        if name == Self.allCategoryName { return "square.grid.2x2" }
        return categories.first(where: { $0.name == name })?.icon ?? AppTabIcon.category(name)
    }

    private func bootstrapFromPersistence() {
        if let cloud = Self.loadFromCloud() {
            isApplyingRemote = true
            categories = cloud
            isApplyingRemote = false
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else {
            persist()
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
        isBootstrapped = true
    }

    private func validate(name: String, ignoring id: UUID?) -> String? {
        if name.isEmpty { return "请输入分类名称" }
        if name == Self.allCategoryName { return "「全部」为系统项，请换一个名称" }
        if categories.contains(where: { $0.name == name && $0.id != id }) {
            return "已有同名分类"
        }
        return nil
    }

    private func remapItems(from oldName: String, to newName: String) {
        let items = PersistenceController.shared.fetchClothingItems(includeDeleted: true)
        var changed = false
        for item in items where item.category == oldName {
            item.category = newName
            changed = true
        }
        if changed {
            PersistenceController.shared.save()
            NotificationCenter.default.post(name: .closetAICategoriesDidChange, object: nil)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(categories),
              let json = String(data: data, encoding: .utf8) else { return }
        PersistenceController.shared.upsertCategoryConfig(payloadJSON: json)
    }

    private func reloadFromCloud() {
        guard isBootstrapped else { return }
        guard let cloud = Self.loadFromCloud(), cloud != categories else { return }
        isApplyingRemote = true
        categories = cloud
        isApplyingRemote = false
        NotificationCenter.default.post(name: .closetAICategoriesDidChange, object: nil)
    }

    private static func loadFromCloud() -> [WardrobeCategory]? {
        guard let json = PersistenceController.shared.fetchCategoryConfig()?.payloadJSON,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WardrobeCategory].self, from: data),
              !decoded.isEmpty else {
            return nil
        }
        return decoded
    }

    private static func loadFromUserDefaults() -> [WardrobeCategory]? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([WardrobeCategory].self, from: data),
              !decoded.isEmpty else {
            return nil
        }
        return decoded
    }
}

extension Notification.Name {
    static let closetAICategoriesDidChange = Notification.Name("closetAICategoriesDidChange")
}
