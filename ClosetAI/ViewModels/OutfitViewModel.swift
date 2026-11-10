import Foundation
import SwiftUI
import Combine

class OutfitViewModel: ObservableObject {
    @Published var savedOutfits: [Outfit] = []
    @Published var errorMessage: String?
    @Published var isTryingOn: Bool = false
    @Published var tryOnResultImage: UIImage?

    private let persistence = PersistenceController.shared
    private let imageService = ImageProcessingService.shared
    private let aliyunService = AliyunService.shared

    let occasions = Occasion.allCases.map { $0.rawValue }

    init() {
        loadSavedOutfits()
    }

    func loadSavedOutfits() {
        savedOutfits = persistence.fetchOutfits()
    }

    // MARK: - Occasion Grouping (v2.0)

    func visibleOutfits(filter: FamilyFilter, clothingItems: [ClothingItem]) -> [Outfit] {
        savedOutfits.filter { matches($0, filter: filter, clothingItems: clothingItems) }
    }

    var occupiedOccasions: [String] {
        occupiedOccasions(in: savedOutfits)
    }

    func occupiedOccasions(in outfits: [Outfit]) -> [String] {
        let used = Set(outfits.compactMap { $0.occasion })
        return occasions.filter { used.contains($0) }
    }

    func outfits(for occasion: String) -> [Outfit] {
        savedOutfits.filter { $0.occasion == occasion }
    }

    func outfits(for occasion: String, in outfits: [Outfit]) -> [Outfit] {
        outfits.filter { $0.occasion == occasion }
    }

    func matches(_ outfit: Outfit, filter: FamilyFilter, clothingItems: [ClothingItem]) -> Bool {
        switch filter {
        case .all:
            return true
        case .unassigned:
            return !isMixedMembership(outfit, clothingItems: clothingItems)
                && resolvedMemberId(for: outfit, clothingItems: clothingItems) == nil
        case .member(let id):
            return !isMixedMembership(outfit, clothingItems: clothingItems)
                && resolvedMemberId(for: outfit, clothingItems: clothingItems) == id
        }
    }

    func resolvedMemberId(for outfit: Outfit, clothingItems: [ClothingItem]) -> UUID? {
        if let stored = outfit.memberId { return stored }
        let ids = Set(outfitItemIDs(outfit))
        let clothes = clothingItems.filter { item in
            guard let id = item.id else { return false }
            return ids.contains(id)
        }
        let unique = Set(clothes.compactMap { $0.memberId })
        if unique.count == 1, clothes.allSatisfy({ $0.memberId != nil }) {
            return unique.first
        }
        return nil
    }

    private func isMixedMembership(_ outfit: Outfit, clothingItems: [ClothingItem]) -> Bool {
        if outfit.memberId != nil { return false }
        let ids = Set(outfitItemIDs(outfit))
        let clothes = clothingItems.filter { item in
            guard let id = item.id else { return false }
            return ids.contains(id)
        }
        let unique = Set(clothes.map { $0.memberId?.uuidString ?? "" })
        return unique.count > 1
    }

    private func outfitItemIDs(_ outfit: Outfit) -> [UUID] {
        (outfit.itemIDs ?? "")
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }

    static func memberId(from items: [ClothingItem], preferred: FamilyFilter) -> UUID? {
        if case .member(let id) = preferred { return id }
        if case .unassigned = preferred { return nil }
        let unique = Set(items.compactMap { $0.memberId })
        if unique.count == 1, items.allSatisfy({ $0.memberId != nil }) {
            return unique.first
        }
        return nil
    }

    // MARK: - Generate Collage

    func generateCollage(for suggestion: OutfitSuggestion) async -> UIImage? {
        let categoryOrder: [String: Int] = [
            "上装": 0, "连衣裙": 0, "外套": 1, "下装": 2, "鞋子": 3, "包包": 4, "配饰": 5
        ]
        let sorted = suggestion.items.sorted {
            (categoryOrder[$0.category ?? ""] ?? 6) < (categoryOrder[$1.category ?? ""] ?? 6)
        }

        var imageDatas: [Data] = []
        var itemDescriptions: [String] = []
        var fallbackItems: [(image: UIImage, category: String)] = []

        for item in sorted {
            let path = item.flatLayImagePath ?? item.originalImagePath ?? ""
            if let image = imageService.loadImage(from: path) {
                fallbackItems.append((image: image, category: item.category ?? ""))
                if let data = image.jpegData(compressionQuality: 0.8) {
                    imageDatas.append(data)
                    itemDescriptions.append(item.subCategory ?? item.category ?? "服装")
                }
            }
        }

        guard !imageDatas.isEmpty else { return nil }

        if AppFeatures.aiEnabled {
            do {
                let resultData = try await aliyunService.generateAICollage(
                    imageDatas: imageDatas,
                    itemDescriptions: itemDescriptions
                )
                if let aiImage = UIImage(data: resultData) { return aiImage }
            } catch {
                print("AI collage error, falling back to Core Graphics: \(error)")
            }
        }

        return imageService.generateOutfitCollage(items: fallbackItems)
    }

    // MARK: - Save Outfit

    func saveOutfit(_ suggestion: OutfitSuggestion, collagePath: String, name: String, occasion: String, tryOnResult: UIImage? = nil, memberId: UUID? = nil) {
        let itemIDs = suggestion.items.compactMap { $0.id }
        let resolvedMemberId = memberId ?? Self.memberId(from: suggestion.items, preferred: .all)
        let model = OutfitModel(
            name: name,
            itemIDs: itemIDs,
            occasion: occasion,
            collagePath: collagePath,
            memberId: resolvedMemberId
        )
        let newOutfit = persistence.createOutfit(from: model)

        // 若同时生成了上身图，一并写入
        if let tryOnImage = tryOnResult {
            let filename = "\(newOutfit.id?.uuidString ?? UUID().uuidString)_tryon.jpg"
            if let path = imageService.saveImageToDocuments(tryOnImage, filename: filename) {
                newOutfit.tryOnResultPath = path
            }
        }

        for item in suggestion.items {
            item.lastRecommendedAt = Date()
        }
        persistence.save()
        loadSavedOutfits()
        NotificationCenter.default.post(name: .closetAIOutfitsDidChange, object: nil)
    }

    // MARK: - Update Outfit

    func updateOutfit(_ outfit: Outfit, name: String, occasion: String) {
        outfit.name = name
        outfit.occasion = occasion
        persistence.save()
        loadSavedOutfits()
        NotificationCenter.default.post(name: .closetAIOutfitsDidChange, object: nil)
    }

    // MARK: - Delete Outfit

    func deleteOutfit(_ outfit: Outfit) {
        if let collagePath = outfit.collagePath, !collagePath.isEmpty {
            let resolvedPath = LocalImageView.resolvePath(collagePath)
            try? FileManager.default.removeItem(atPath: resolvedPath)
        }
        if let tryOnPath = outfit.tryOnResultPath, !tryOnPath.isEmpty {
            let resolvedPath = LocalImageView.resolvePath(tryOnPath)
            try? FileManager.default.removeItem(atPath: resolvedPath)
        }
        persistence.deleteOutfit(outfit)
        loadSavedOutfits()
        NotificationCenter.default.post(name: .closetAIOutfitsDidChange, object: nil)
    }

    // MARK: - Save Try-On Result

    func saveTryOnResult(_ image: UIImage, for outfit: Outfit) {
        let filename = "\(outfit.id?.uuidString ?? UUID().uuidString)_tryon.jpg"
        if let oldPath = outfit.tryOnResultPath, !oldPath.isEmpty {
            try? FileManager.default.removeItem(atPath: LocalImageView.resolvePath(oldPath))
        }
        if let path = imageService.saveImageToDocuments(image, filename: filename) {
            outfit.tryOnResultPath = path
            persistence.save()
            loadSavedOutfits()
        }
    }

    // MARK: - Virtual Try-On

    func performVirtualTryOn(personImage: UIImage, items: [ClothingItem]) async {
        guard AppFeatures.aiEnabled else {
            await MainActor.run { errorMessage = "虚拟试穿已暂时关闭" }
            return
        }
        await MainActor.run { isTryingOn = true; tryOnResultImage = nil; errorMessage = nil }
        do {
            guard let personData = personImage.jpegData(compressionQuality: 0.8) else { return }
            var clothingDatas: [Data] = []
            for item in items {
                let path = item.flatLayImagePath ?? item.originalImagePath ?? ""
                if let img = imageService.loadImage(from: path),
                   let data = img.jpegData(compressionQuality: 0.8) {
                    clothingDatas.append(data)
                }
            }
            let resultData = try await aliyunService.virtualTryOn(
                personImageData: personData,
                clothingItems: clothingDatas
            )
            let resultImage = UIImage(data: resultData)
            await MainActor.run { self.tryOnResultImage = resultImage; self.isTryingOn = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isTryingOn = false }
        }
    }
}

// MARK: - OutfitSuggestion

struct OutfitSuggestion: Identifiable {
    let id = UUID()
    let items: [ClothingItem]
    let score: Double
}
