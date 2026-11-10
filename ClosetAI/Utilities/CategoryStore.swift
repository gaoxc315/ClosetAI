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
        didSet { persist() }
    }

    var names: [String] {
        categories.map(\.name)
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([WardrobeCategory].self, from: data),
           !decoded.isEmpty {
            categories = decoded
        } else {
            categories = Self.defaultCategories
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
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

extension Notification.Name {
    static let closetAICategoriesDidChange = Notification.Name("closetAICategoriesDidChange")
}
