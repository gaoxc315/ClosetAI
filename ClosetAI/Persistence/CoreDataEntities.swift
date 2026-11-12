import Foundation
import CoreData

// MARK: - JSON String helpers (CloudKit-compatible [String] storage)

enum StringArrayJSON {
    static func encode(_ array: [String]?) -> String? {
        guard let array else { return nil }
        guard let data = try? JSONEncoder().encode(array) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ value: Any?) -> [String] {
        if let array = value as? [String] { return array }
        if let string = value as? String, let data = string.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        if let data = value as? Data,
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        return []
    }
}

// MARK: - ClothingItem

@objc(ClothingItem)
public class ClothingItem: NSManagedObject {}

extension ClothingItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ClothingItem> {
        return NSFetchRequest<ClothingItem>(entityName: "ClothingItem")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var originalImagePath: String?
    @NSManaged public var flatLayImagePath: String?
    @NSManaged public var originalImageData: Data?
    @NSManaged public var flatLayImageData: Data?
    @NSManaged public var ossKey: String?
    @NSManaged public var category: String?
    @NSManaged public var subCategory: String?
    @NSManaged public var colors: String?
    @NSManaged public var pattern: String?
    @NSManaged public var styles: String?
    @NSManaged public var seasons: String?
    @NSManaged public var occasions: String?
    @NSManaged public var wearCount: Int32
    @NSManaged public var lastWornDate: Date?
    @NSManaged public var lastRecommendedAt: Date?
    @NSManaged public var memberId: UUID?
    @NSManaged public var notes: String?
    @NSManaged public var isSoftDeleted: Bool
    @NSManaged public var createdAt: Date?

    var colorsList: [String] {
        get { StringArrayJSON.decode(colors) }
        set { colors = StringArrayJSON.encode(newValue) }
    }

    var stylesList: [String] {
        get { StringArrayJSON.decode(styles) }
        set { styles = StringArrayJSON.encode(newValue) }
    }

    var seasonsList: [String] {
        get { StringArrayJSON.decode(seasons) }
        set { seasons = StringArrayJSON.encode(newValue) }
    }

    var occasionsList: [String] {
        get { StringArrayJSON.decode(occasions) }
        set { occasions = StringArrayJSON.encode(newValue) }
    }
}

extension ClothingItem: Identifiable {}

// MARK: - FamilyMember

@objc(FamilyMember)
public class FamilyMember: NSManagedObject {}

extension FamilyMember {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FamilyMember> {
        return NSFetchRequest<FamilyMember>(entityName: "FamilyMember")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date?
}

extension FamilyMember: Identifiable {}

// MARK: - Outfit

@objc(Outfit)
public class Outfit: NSManagedObject {}

extension Outfit {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Outfit> {
        return NSFetchRequest<Outfit>(entityName: "Outfit")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var itemIDs: String?
    @NSManaged public var occasion: String?
    @NSManaged public var collagePath: String?
    @NSManaged public var collageData: Data?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var memberId: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var tryOnResultPath: String?
    @NSManaged public var tryOnResultData: Data?
}

extension Outfit: Identifiable {}

// MARK: - WearLog

@objc(WearLog)
public class WearLog: NSManagedObject {}

extension WearLog {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<WearLog> {
        return NSFetchRequest<WearLog>(entityName: "WearLog")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var outfitID: UUID?
    @NSManaged public var itemIDs: String?
    @NSManaged public var wornDate: Date?
    @NSManaged public var note: String?
}

extension WearLog: Identifiable {}

// MARK: - CategoryConfig

@objc(CategoryConfig)
public class CategoryConfig: NSManagedObject {}

extension CategoryConfig {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategoryConfig> {
        return NSFetchRequest<CategoryConfig>(entityName: "CategoryConfig")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var payloadJSON: String?
    @NSManaged public var updatedAt: Date?
}

extension CategoryConfig: Identifiable {}
