import Foundation
import SwiftUI
import Combine
import CoreData

extension Notification.Name {
    static let closetAIOutfitsDidChange = Notification.Name("closetAIOutfitsDidChange")
}

enum FamilyFilter: Equatable, Hashable {
    case all
    case unassigned
    case member(UUID)
}

class WardrobeViewModel: ObservableObject {
    @Published var items: [ClothingItem] = []
    @Published var filteredItems: [ClothingItem] = []
    @Published var familyMembers: [FamilyMember] = []
    @Published var selectedFilter: FamilyFilter = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published private(set) var savedOutfits: [Outfit] = []

    private var cancellables = Set<AnyCancellable>()
    private let persistence = PersistenceController.shared
    private let imageService = ImageProcessingService.shared
    private let aliyunService = AliyunService.shared

    private static let filterDefaultsKey = "closetai.familyFilter"

    init() {
        persistence.seedDefaultFamilyMemberIfNeeded()
        loadItems()
        restoreFilter()
        setupSearch()
        NotificationCenter.default.addObserver(
            self, selector: #selector(outfitsDidChange),
            name: .closetAIOutfitsDidChange, object: nil
        )
    }

    func loadItems() {
        items = persistence.fetchClothingItems(includeDeleted: false)
        familyMembers = persistence.fetchFamilyMembers()
        savedOutfits = persistence.fetchOutfits()
        applyFilters()
    }

    @objc private func outfitsDidChange() {
        savedOutfits = persistence.fetchOutfits()
    }

    private func setupSearch() {
        Publishers.CombineLatest3($searchText, $items, $selectedFilter)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.applyFilters() }
            .store(in: &cancellables)
    }

    func selectFilter(_ filter: FamilyFilter) {
        selectedFilter = filter
        persistFilter()
        applyFilters()
    }

    func memberName(for item: ClothingItem) -> String {
        guard let memberId = item.memberId else { return "未分配" }
        return familyMembers.first(where: { $0.id == memberId })?.name ?? "未分配"
    }

    func addFamilyMember(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        persistence.createFamilyMember(name: trimmed)
        loadItems()
    }

    func renameFamilyMember(_ member: FamilyMember, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        persistence.renameFamilyMember(member, name: trimmed)
        objectWillChange.send()
    }

    func deleteFamilyMember(_ member: FamilyMember) {
        if case .member(let id) = selectedFilter, id == member.id {
            selectFilter(.all)
        }
        persistence.deleteFamilyMember(member)
        loadItems()
    }

    func updateItemMember(_ item: ClothingItem, memberId: UUID?) {
        item.memberId = memberId
        persistence.save()
        loadItems()
    }

    /// 当前筛选下新衣物应归属的成员；「全部」时返回 nil，由界面再选。
    var memberIdForNewItem: UUID? {
        if case .member(let id) = selectedFilter { return id }
        return nil
    }

    var needsMemberPickForNewItem: Bool {
        if case .member = selectedFilter { return false }
        return true
    }

    private func persistFilter() {
        switch selectedFilter {
        case .all:
            UserDefaults.standard.set("all", forKey: Self.filterDefaultsKey)
        case .unassigned:
            UserDefaults.standard.set("unassigned", forKey: Self.filterDefaultsKey)
        case .member(let id):
            UserDefaults.standard.set(id.uuidString, forKey: Self.filterDefaultsKey)
        }
    }

    private func restoreFilter() {
        let raw = UserDefaults.standard.string(forKey: Self.filterDefaultsKey) ?? "all"
        switch raw {
        case "all":
            selectedFilter = .all
        case "unassigned":
            selectedFilter = .unassigned
        default:
            if let id = UUID(uuidString: raw), familyMembers.contains(where: { $0.id == id }) {
                selectedFilter = .member(id)
            } else {
                selectedFilter = .all
            }
        }
    }

    private func applyFilters() {
        var result = items.filter { !$0.isSoftDeleted }
        switch selectedFilter {
        case .all:
            break
        case .unassigned:
            result = result.filter { $0.memberId == nil }
        case .member(let id):
            result = result.filter { $0.memberId == id }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                ($0.category?.lowercased().contains(query) == true) ||
                ($0.subCategory?.lowercased().contains(query) == true) ||
                ($0.notes?.lowercased().contains(query) == true) ||
                (memberName(for: $0).lowercased().contains(query)) ||
                (($0.colors as? [String])?.joined().lowercased().contains(query) == true) ||
                (($0.styles as? [String])?.joined().lowercased().contains(query) == true)
            }
        }
        filteredItems = result
    }

    // MARK: - Section Helpers

    func items(inCategories categories: [String]) -> [ClothingItem] {
        filteredItems.filter { categories.contains($0.category ?? "") }
    }

    func otherItems(excludingCategories excluded: [String]) -> [ClothingItem] {
        filteredItems.filter { !excluded.contains($0.category ?? "") }
    }

    // MARK: - Idle Logic (v2.0: based on outfit association)

    var idleItemIDs: Set<UUID> {
        let usedIDs = Set(savedOutfits.flatMap { outfit -> [UUID] in
            (outfit.itemIDs ?? "")
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        })
        let allIDs = Set(items.filter { !$0.isSoftDeleted }.compactMap { $0.id })
        return allIDs.subtracting(usedIDs)
    }

    func outfits(containing item: ClothingItem) -> [Outfit] {
        guard let itemID = item.id?.uuidString else { return [] }
        return savedOutfits.filter { outfit in
            (outfit.itemIDs ?? "")
                .split(separator: ",")
                .map { String($0) }
                .contains(itemID)
        }
    }

    // MARK: - Statistics

    var totalCount: Int { items.filter { !$0.isSoftDeleted }.count }
    var scopedCount: Int { filteredItems.count }
    var idleCount: Int {
        filteredItems.filter { idleItemIDs.contains($0.id ?? UUID()) }.count
    }

    /// 衣物「上次穿着」日期：取包含该衣物的所有穿搭中最晚的 createdAt
    func lastOutfitDate(for item: ClothingItem) -> Date? {
        outfits(containing: item)
            .compactMap { $0.createdAt }
            .max()
    }

    /// 近 90 天未穿：从未加入穿搭，或最近穿搭创建时间超过 90 天
    var notWornRecently: [ClothingItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        return items.filter { item in
            guard !item.isSoftDeleted else { return false }
            guard let lastWorn = lastOutfitDate(for: item) else { return true }
            return lastWorn < cutoff
        }
    }

    var colorDistribution: [String: Int] {
        var dist: [String: Int] = [:]
        for item in items where !item.isSoftDeleted {
            for color in (item.colors as? [String]) ?? [] {
                dist[color, default: 0] += 1
            }
        }
        return dist
    }

    // MARK: - Add Item with AI Processing

    func processAndAddItem(image: UIImage, memberId: UUID? = nil) async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let preprocessed = imageService.preprocessImage(image)
            // Minimum size guard — catches blank/accidental captures before expensive processing
            guard let cg = preprocessed.cgImage, cg.width > 100, cg.height > 100 else {
                await MainActor.run { errorMessage = "图片太小，请重新拍摄"; isLoading = false }
                return
            }
            let noBG = await imageService.removeBackground(from: preprocessed)
            let flatLay = imageService.generateFlatLayImage(from: noBG)
            let itemID = UUID()
            let originalFilename = "\(itemID.uuidString)_original.jpg"
            let flatLayFilename = "\(itemID.uuidString)_flatlay.jpg"
            guard let originalPath = imageService.saveImageToDocuments(image, filename: originalFilename),
                  let flatLayPath = imageService.saveImageToDocuments(flatLay, filename: flatLayFilename) else {
                throw NSError(domain: "ClosetAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "保存图片失败"])
            }
            var tags = ClothingTags()
            if AppFeatures.aiEnabled, let imageData = image.jpegData(compressionQuality: 0.8) {
                do { tags = try await aliyunService.autoTagClothing(imageData: imageData) }
                catch { print("Auto-tag error: \(error)") }
            }
            let model = ClothingItemModel(
                id: itemID,
                originalImagePath: originalPath,
                flatLayImagePath: flatLayPath,
                category: tags.category.isEmpty ? "其他" : tags.category,
                subCategory: tags.subCategory,
                colors: tags.colors,
                pattern: tags.pattern,
                styles: tags.styles,
                seasons: tags.seasons,
                occasions: tags.occasions,
                memberId: memberId,
                notes: tags.notes
            )
            persistence.createClothingItem(from: model)
            await MainActor.run { self.loadItems(); self.isLoading = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
        }
    }

    func softDelete(_ item: ClothingItem) {
        persistence.deleteClothingItem(item, soft: true)
        loadItems()
    }

    func restore(_ item: ClothingItem) {
        persistence.restoreClothingItem(item)
        loadItems()
    }

    func permanentDelete(_ item: ClothingItem) {
        if let path = item.originalImagePath {
            try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(path))
        }
        if let path = item.flatLayImagePath {
            try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(path))
        }
        persistence.deleteClothingItem(item, soft: false)
        loadItems()
    }

    func updateItem(_ item: ClothingItem, tags: ClothingTags) {
        item.category = tags.category
        item.subCategory = tags.subCategory
        item.colors = tags.colors as NSObject
        item.pattern = tags.pattern
        item.styles = tags.styles as NSObject
        item.seasons = tags.seasons as NSObject
        item.occasions = tags.occasions as NSObject
        item.notes = tags.notes
        persistence.save()
        loadItems()
    }

    func recordWear(for item: ClothingItem) {
        item.wearCount += 1
        item.lastWornDate = Date()
        persistence.save()
        let log = WearLogModel(itemIDs: [item.id ?? UUID()])
        persistence.createWearLog(from: log)
        loadItems()
    }
}
