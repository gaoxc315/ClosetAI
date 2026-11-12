import CoreData
import Foundation
import CloudKit
import Combine

extension Notification.Name {
    static let closetAICloudDidChange = Notification.Name("closetAICloudDidChange")
}

enum CloudSyncStatus: Equatable {
    case available
    case syncing
    case unavailable(String)
    case localOnly
}

// MARK: - PersistenceController

final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    static let cloudKitContainerID = "iCloud.com.gaoxiancheng.closetai"
    private static let migrationFlagKey = "closetai.didMigrateToCloudKitModel"
    private static let imageBackfillFlagKey = "closetai.didBackfillImageBinary"

    let container: NSPersistentCloudKitContainer

    @Published private(set) var syncStatus: CloudSyncStatus = .localOnly
    @Published private(set) var cloudKitEnabled: Bool = false

    private var remoteChangeObserver: NSObjectProtocol?
    private var eventObserver: NSObjectProtocol?
    private var didScheduleMemberSeed = false

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "ClosetAI")

        if inMemory {
            let description = container.persistentStoreDescriptions.first!
            description.url = URL(fileURLWithPath: "/dev/null")
            description.cloudKitContainerOptions = nil
            cloudKitEnabled = false
            syncStatus = .localOnly
        } else {
            configureStoreDescriptions()
        }

        container.loadPersistentStores { [weak self] storeDesc, error in
            guard let self else { return }
            if let error = error as NSError? {
                print("‼️ Core Data load error: \(error.code) \(error.domain) — \(error.localizedDescription)")
                print("‼️ userInfo: \(error.userInfo)")
                self.recoverFromLoadFailure(storeDesc: storeDesc)
            } else {
                print("✅ Core Data loaded: \(storeDesc.url?.lastPathComponent ?? "unknown") cloudKit=\(self.cloudKitEnabled)")
                UserDefaults.standard.set(true, forKey: Self.migrationFlagKey)
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"

        if !inMemory {
            observeRemoteChanges()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.backfillImageBinaryIfNeeded()
                self?.materializeImagesIfNeeded()
                self?.scheduleDefaultMemberSeedIfNeeded()
            }
        }
    }

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
    }

    // MARK: - Store configuration

    private func configureStoreDescriptions() {
        guard let description = container.persistentStoreDescriptions.first else { return }
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        if iCloudAvailable {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID
            )
            cloudKitEnabled = true
            syncStatus = .syncing
            verifyCloudKitAccount()
        } else {
            description.cloudKitContainerOptions = nil
            cloudKitEnabled = false
            syncStatus = .unavailable("未登录 iCloud")
        }
    }

    private func verifyCloudKitAccount() {
        CKContainer(identifier: Self.cloudKitContainerID).accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .available:
                    self.syncStatus = .available
                case .noAccount:
                    self.syncStatus = .unavailable("未登录 iCloud")
                    self.cloudKitEnabled = false
                case .restricted:
                    self.syncStatus = .unavailable("iCloud 受限制")
                case .couldNotDetermine:
                    self.syncStatus = .unavailable(error?.localizedDescription ?? "无法确定 iCloud 状态")
                case .temporarilyUnavailable:
                    self.syncStatus = .unavailable("iCloud 暂时不可用")
                @unknown default:
                    self.syncStatus = .unavailable("未知 iCloud 状态")
                }
            }
        }
    }

    private func recoverFromLoadFailure(storeDesc: NSPersistentStoreDescription) {
        guard let storeURL = storeDesc.url else { return }
        let coordinator = container.persistentStoreCoordinator
        do {
            try coordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType, options: nil)
            _ = try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: storeDesc.options
            )
            print("✅ Core Data store rebuilt after migration failure")
            UserDefaults.standard.set(true, forKey: Self.migrationFlagKey)
        } catch {
            print("‼️ Core Data store rebuild failed: \(error)")
            DispatchQueue.main.async {
                self.syncStatus = .unavailable("本地数据库无法打开")
            }
        }
    }

    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.handleRemoteChange()
        }

        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            if event.endDate == nil {
                self.syncStatus = .syncing
            } else if self.cloudKitEnabled {
                self.syncStatus = event.error == nil ? .available : .unavailable(event.error?.localizedDescription ?? "同步失败")
            }
            if event.endDate != nil, event.error == nil {
                self.handleRemoteChange()
            }
        }
    }

    private func handleRemoteChange() {
        materializeImagesIfNeeded()
        NotificationCenter.default.post(name: .closetAICloudDidChange, object: nil)
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Core Data save error: \(error)")
        }
    }

    // MARK: - Image materialization & backfill

    func materializeImagesIfNeeded() {
        let context = container.viewContext
        context.performAndWait {
            let clothes = (try? context.fetch(ClothingItem.fetchRequest())) ?? []
            for item in clothes {
                materialize(path: item.originalImagePath, data: item.originalImageData)
                materialize(path: item.flatLayImagePath, data: item.flatLayImageData)
            }
            let outfits = (try? context.fetch(Outfit.fetchRequest())) ?? []
            for outfit in outfits {
                materialize(path: outfit.collagePath, data: outfit.collageData)
                materialize(path: outfit.tryOnResultPath, data: outfit.tryOnResultData)
            }
        }
    }

    private func materialize(path: String?, data: Data?) {
        guard let data, !data.isEmpty else { return }
        guard let path, !path.isEmpty else { return }
        let resolved = LocalImageView.resolvePath(path)
        if FileManager.default.fileExists(atPath: resolved) { return }
        let url = URL(fileURLWithPath: resolved)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    func backfillImageBinaryIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.imageBackfillFlagKey) else { return }
        let context = container.viewContext
        var changed = false
        context.performAndWait {
            let clothes = (try? context.fetch(ClothingItem.fetchRequest())) ?? []
            for item in clothes {
                if item.originalImageData == nil,
                   let path = item.originalImagePath,
                   let data = fileData(at: LocalImageView.resolvePath(path)) {
                    item.originalImageData = data
                    changed = true
                }
                if item.flatLayImageData == nil,
                   let path = item.flatLayImagePath,
                   let data = fileData(at: LocalImageView.resolvePath(path)) {
                    item.flatLayImageData = data
                    changed = true
                }
            }
            let outfits = (try? context.fetch(Outfit.fetchRequest())) ?? []
            for outfit in outfits {
                if outfit.collageData == nil,
                   let path = outfit.collagePath,
                   let data = fileData(at: LocalImageView.resolvePath(path)) {
                    outfit.collageData = data
                    changed = true
                }
                if outfit.tryOnResultData == nil,
                   let path = outfit.tryOnResultPath,
                   let data = fileData(at: LocalImageView.resolvePath(path)) {
                    outfit.tryOnResultData = data
                    changed = true
                }
            }
            if changed {
                try? context.save()
            }
        }
        UserDefaults.standard.set(true, forKey: Self.imageBackfillFlagKey)
    }

    private func fileData(at path: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    // MARK: - Delayed default member seed (avoid CloudKit duplicates)

    func seedDefaultFamilyMemberIfNeeded() {
        scheduleDefaultMemberSeedIfNeeded()
    }

    private func scheduleDefaultMemberSeedIfNeeded() {
        guard !didScheduleMemberSeed else { return }
        didScheduleMemberSeed = true
        let delay: TimeInterval = cloudKitEnabled ? 3.0 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let existing = self.fetchFamilyMembers()
            guard existing.isEmpty else { return }
            _ = self.createFamilyMember(name: "我")
            NotificationCenter.default.post(name: .closetAICloudDidChange, object: nil)
        }
    }

    // MARK: - ClothingItem CRUD

    func createClothingItem(from model: ClothingItemModel, originalData: Data? = nil, flatLayData: Data? = nil) {
        let context = container.viewContext
        let entity = ClothingItem(context: context)
        entity.id = model.id
        entity.originalImagePath = model.originalImagePath
        entity.flatLayImagePath = model.flatLayImagePath
        entity.originalImageData = originalData ?? dataFromDocuments(model.originalImagePath)
        entity.flatLayImageData = flatLayData ?? dataFromDocuments(model.flatLayImagePath)
        entity.ossKey = model.ossKey
        entity.category = model.category
        entity.subCategory = model.subCategory
        entity.colorsList = model.colors
        entity.pattern = model.pattern
        entity.stylesList = model.styles
        entity.seasonsList = model.seasons
        entity.occasionsList = model.occasions
        entity.wearCount = Int32(model.wearCount)
        entity.lastWornDate = model.lastWornDate
        entity.lastRecommendedAt = model.lastRecommendedAt
        entity.memberId = model.memberId
        entity.notes = model.notes
        entity.isSoftDeleted = model.isSoftDeleted
        entity.createdAt = model.createdAt
        save()
    }

    private func dataFromDocuments(_ path: String?) -> Data? {
        guard let path, !path.isEmpty else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: LocalImageView.resolvePath(path)))
    }

    func fetchClothingItems(includeDeleted: Bool = false) -> [ClothingItem] {
        let request: NSFetchRequest<ClothingItem> = ClothingItem.fetchRequest()
        if !includeDeleted {
            request.predicate = NSPredicate(format: "isSoftDeleted == NO")
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ClothingItem.createdAt, ascending: false)]
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Fetch error: \(error)")
            return []
        }
    }

    func deleteClothingItem(_ item: ClothingItem, soft: Bool = true) {
        if soft {
            item.isSoftDeleted = true
        } else {
            container.viewContext.delete(item)
        }
        save()
    }

    func restoreClothingItem(_ item: ClothingItem) {
        item.isSoftDeleted = false
        save()
    }

    // MARK: - FamilyMember CRUD

    func fetchFamilyMembers() -> [FamilyMember] {
        let request: NSFetchRequest<FamilyMember> = FamilyMember.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \FamilyMember.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \FamilyMember.createdAt, ascending: true)
        ]
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Fetch family members error: \(error)")
            return []
        }
    }

    @discardableResult
    func createFamilyMember(name: String) -> FamilyMember {
        let nextOrder = Int32(fetchFamilyMembers().count)
        let context = container.viewContext
        let entity = FamilyMember(context: context)
        entity.id = UUID()
        entity.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entity.sortOrder = nextOrder
        entity.createdAt = Date()
        save()
        return entity
    }

    func renameFamilyMember(_ member: FamilyMember, name: String) {
        member.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func reorderFamilyMembers(_ members: [FamilyMember]) {
        for (index, member) in members.enumerated() {
            member.sortOrder = Int32(index)
        }
        save()
    }

    func deleteFamilyMember(_ member: FamilyMember) {
        let memberId = member.id
        let clothes = fetchClothingItems(includeDeleted: true).filter { $0.memberId == memberId }
        for item in clothes {
            item.memberId = nil
        }
        for outfit in fetchOutfits() where outfit.memberId == memberId {
            outfit.memberId = nil
        }
        container.viewContext.delete(member)
        save()
    }

    // MARK: - Outfit CRUD

    @discardableResult
    func createOutfit(from model: OutfitModel, collageData: Data? = nil, tryOnData: Data? = nil) -> Outfit {
        let context = container.viewContext
        let entity = Outfit(context: context)
        entity.id = model.id
        entity.name = model.name
        entity.itemIDs = model.itemIDs.map { $0.uuidString }.joined(separator: ",")
        entity.occasion = model.occasion
        entity.collagePath = model.collagePath
        entity.collageData = collageData ?? dataFromDocuments(model.collagePath)
        entity.isFavorite = model.isFavorite
        entity.memberId = model.memberId
        entity.createdAt = model.createdAt
        entity.tryOnResultData = tryOnData
        save()
        return entity
    }

    func fetchOutfits() -> [Outfit] {
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.createdAt, ascending: false)]
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Fetch outfits error: \(error)")
            return []
        }
    }

    func deleteOutfit(_ outfit: Outfit) {
        container.viewContext.delete(outfit)
        save()
    }

    // MARK: - WearLog CRUD

    func createWearLog(from model: WearLogModel) {
        let context = container.viewContext
        let entity = WearLog(context: context)
        entity.id = model.id
        entity.outfitID = model.outfitID
        entity.itemIDs = model.itemIDs.map { $0.uuidString }.joined(separator: ",")
        entity.wornDate = model.wornDate
        entity.note = model.note
        save()
    }

    func fetchWearLogs() -> [WearLog] {
        let request: NSFetchRequest<WearLog> = WearLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WearLog.wornDate, ascending: false)]
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Fetch logs error: \(error)")
            return []
        }
    }

    // MARK: - CategoryConfig

    func fetchCategoryConfig() -> CategoryConfig? {
        let request: NSFetchRequest<CategoryConfig> = CategoryConfig.fetchRequest()
        request.fetchLimit = 1
        return try? container.viewContext.fetch(request).first
    }

    @discardableResult
    func upsertCategoryConfig(payloadJSON: String) -> CategoryConfig {
        let context = container.viewContext
        let config = fetchCategoryConfig() ?? CategoryConfig(context: context)
        if config.id == nil {
            config.id = UUID()
        }
        config.payloadJSON = payloadJSON
        config.updatedAt = Date()
        save()
        return config
    }
}
