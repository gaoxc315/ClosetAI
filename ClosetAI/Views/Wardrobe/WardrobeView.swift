import SwiftUI

// MARK: - Category Section Definition

private struct CategorySection {
    let name: String
    let categories: [String]
    let isOther: Bool

    static let all: [CategorySection] = [
        CategorySection(name: "上装", categories: ["上装"], isOther: false),
        CategorySection(name: "外套", categories: ["外套"], isOther: false),
        CategorySection(name: "连衣裙", categories: ["连衣裙"], isOther: false),
        CategorySection(name: "下装", categories: ["下装"], isOther: false),
        CategorySection(name: "鞋子", categories: ["鞋子"], isOther: false),
        CategorySection(name: "包包", categories: ["包包"], isOther: false),
        CategorySection(name: "配饰", categories: ["配饰"], isOther: false),
        CategorySection(name: "其他", categories: ["其他"], isOther: true),
    ]

    // The categories covered by all non-other sections
    static let standardCategories: [String] = all
        .filter { !$0.isOther }
        .flatMap { $0.categories }
}

// MARK: - WardrobeView

struct WardrobeView: View {
    @EnvironmentObject var viewModel: WardrobeViewModel
    @EnvironmentObject var outfitVM: OutfitViewModel

    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedImage: UIImage?
    @State private var selectedItem: ClothingItem?
    @State private var showDeletedItems = false
    @State private var showAllSectionTitle: String? = nil
    @State private var showAllSectionItems: [ClothingItem] = []
    @State private var showSearch = false
    @State private var itemToDelete: ClothingItem? = nil
    @State private var showManageMembers = false
    @State private var pendingImage: UIImage?
    @State private var showOwnerPicker = false
    @State private var selectedCategoryName: String = "全部"

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGray6).ignoresSafeArea()

                VStack(spacing: 0) {
                    // 搜索栏（按需呼出）
                    if showSearch {
                        searchBar
                    }

                    if viewModel.searchText.isEmpty {
                        FamilyMemberBar {
                            showManageMembers = true
                        }
                    }

                    HStack(spacing: 0) {
                        if viewModel.searchText.isEmpty {
                            categoryRail
                        }

                        ScrollView {
                            VStack(spacing: 0) {
                                if viewModel.searchText.isEmpty {
                                    statsBar
                                        .padding(.horizontal, 12)
                                        .padding(.top, 8)
                                        .padding(.bottom, 4)
                                }

                                if viewModel.searchText.isEmpty {
                                    if selectedCategoryName == "全部" {
                                        sectionLayout
                                    } else {
                                        categoryGrid
                                    }
                                } else {
                                    searchContent
                                }
                            }
                            .padding(.bottom, 100)
                        }
                        .scrollDismissesKeyboard(.immediately)
                    }
                }

                // Loading toast
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        loadingToast
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isLoading)
                    .zIndex(10)
                }
            }
            .navigationTitle("衣橱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    trashButton
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    searchButton
                }
            }
            .onChange(of: selectedImage) { _, image in
                guard let image = image else { return }
                selectedImage = nil
                if viewModel.needsMemberPickForNewItem {
                    pendingImage = image
                    showOwnerPicker = true
                } else {
                    let memberId = viewModel.memberIdForNewItem
                    Task { await viewModel.processAndAddItem(image: image, memberId: memberId) }
                }
            }
            .alert("确认删除？", isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            )) {
                Button("删除单品", role: .destructive) {
                    if let item = itemToDelete { viewModel.softDelete(item) }
                    itemToDelete = nil
                }
                Button("取消", role: .cancel) { itemToDelete = nil }
            } message: {
                Text("删除后可在「已删除」中恢复")
            }
        }
        .errorToast($viewModel.errorMessage)
        // FAB overlay (outside NavigationStack for proper layering)
        .overlay(alignment: .bottomTrailing) {
            fabButton
        }
        .sheet(isPresented: $showCamera) {
            CameraView(image: $selectedImage)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(images: Binding(
                get: { selectedImage.map { [$0] } ?? [] },
                set: { selectedImage = $0.first }
            ))
        }
        .sheet(item: $selectedItem) { item in
            ClothingDetailView(item: item)
                .environmentObject(viewModel)
                .environmentObject(outfitVM)
        }
        .sheet(isPresented: $showDeletedItems) {
            DeletedItemsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showManageMembers) {
            ManageFamilyMembersView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showOwnerPicker) {
            AssignMemberSheet { memberId in
                guard let image = pendingImage else { return }
                pendingImage = nil
                Task { await viewModel.processAndAddItem(image: image, memberId: memberId) }
            }
            .environmentObject(viewModel)
            .onDisappear {
                pendingImage = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { showAllSectionTitle != nil },
            set: { if !$0 { showAllSectionTitle = nil } }
        )) {
            CategoryGridSheet(
                title: showAllSectionTitle ?? "",
                items: showAllSectionItems,
                idleItemIDs: viewModel.idleItemIDs,
                onSelect: { selectedItem = $0 },
                onDelete: { viewModel.softDelete($0) }
            )
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 5) {
            Text("共 \(visibleItemCount) 件")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("·")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button {
                let idleItems = itemsForSelectedCategory.filter {
                    viewModel.idleItemIDs.contains($0.id ?? UUID())
                }
                showAllSectionItems = idleItems
                showAllSectionTitle = "未搭配"
            } label: {
                Text("未搭配 \(visibleIdleCount) 件")
                    .font(.system(size: 12))
                    .foregroundColor(visibleIdleCount > 0 ? AppColors.idle : .secondary)
            }
            .disabled(visibleIdleCount == 0)
            Spacer()
        }
    }

    private var visibleItemCount: Int {
        itemsForSelectedCategory.count
    }

    private var visibleIdleCount: Int {
        itemsForSelectedCategory.filter { viewModel.idleItemIDs.contains($0.id ?? UUID()) }.count
    }

    private var itemsForSelectedCategory: [ClothingItem] {
        items(forCategoryName: selectedCategoryName)
    }

    private func items(forCategoryName name: String) -> [ClothingItem] {
        guard let section = CategorySection.all.first(where: { $0.name == name }) else {
            return viewModel.filteredItems
        }
        if section.isOther {
            return viewModel.otherItems(excludingCategories: CategorySection.standardCategories)
        }
        return viewModel.items(inCategories: section.categories)
    }

    // MARK: - Category Rail

    private var categoryRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                categoryRailButton(name: "全部", icon: "square.grid.2x2", count: viewModel.filteredItems.count)
                ForEach(CategorySection.all, id: \.name) { section in
                    categoryRailButton(
                        name: section.name,
                        icon: iconName(for: section.name),
                        count: items(forCategoryName: section.name).count
                    )
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 80)
        }
        .frame(width: 68)
        .background(Color(.systemBackground))
    }

    private func categoryRailButton(name: String, icon: String, count: Int) -> some View {
        let selected = selectedCategoryName == name
        return Button {
            selectedCategoryName = name
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: selected ? .semibold : .regular))
                Text(name)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9))
                        .foregroundColor(selected ? AppColors.accent.opacity(0.85) : .secondary)
                }
            }
            .foregroundColor(selected ? AppColors.accent : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? AppColors.accent.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    private func iconName(for category: String) -> String {
        switch category {
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

    // MARK: - Category Grid

    private var categoryGrid: some View {
        Group {
            if itemsForSelectedCategory.isEmpty {
                emptyStateView
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(itemsForSelectedCategory) { item in
                        ClothingItemCard(
                            item: item,
                            isIdle: viewModel.idleItemIDs.contains(item.id ?? UUID())
                        )
                        .frame(maxWidth: .infinity)
                        .onTapGesture { selectedItem = item }
                        .contextMenu {
                            Button(role: .destructive) {
                                itemToDelete = item
                            } label: {
                                Label("删除单品", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Section Layout

    private var sectionLayout: some View {
        VStack(spacing: 12) {
            ForEach(CategorySection.all, id: \.name) { section in
                let sectionItems: [ClothingItem] = section.isOther
                    ? viewModel.otherItems(excludingCategories: CategorySection.standardCategories)
                    : viewModel.items(inCategories: section.categories)

                if !sectionItems.isEmpty {
                    wardrobeSectionCard(
                        name: section.name,
                        items: sectionItems
                    )
                }
            }

            if viewModel.filteredItems.isEmpty {
                emptyStateView
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func wardrobeSectionCard(name: String, items: [ClothingItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("\(items.count)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    showAllSectionItems = items
                    showAllSectionTitle = name
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(items) { item in
                        ClothingItemCard(
                            item: item,
                            isIdle: viewModel.idleItemIDs.contains(item.id ?? UUID())
                        )
                        .onTapGesture { selectedItem = item }
                        .contextMenu {
                            Button(role: .destructive) {
                                itemToDelete = item
                            } label: {
                                Label("删除单品", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Search Results

    private var searchContent: some View {
        Group {
            if viewModel.filteredItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(Color(.systemGray4))
                    Text("没有找到相关衣物")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 80)
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.filteredItems) { item in
                        ClothingItemCard(
                            item: item,
                            isIdle: viewModel.idleItemIDs.contains(item.id ?? UUID())
                        )
                        .frame(maxWidth: .infinity)
                        .onTapGesture { selectedItem = item }
                        .contextMenu {
                            Button(role: .destructive) {
                                itemToDelete = item
                            } label: {
                                Label("删除单品", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "hanger")
                .font(.system(size: 52))
                .foregroundColor(Color(.systemGray4))
            Text(emptyTitle)
                .font(.title3)
                .fontWeight(.medium)
            Text("点击右下角 + 添加衣物，或点「管理」增加家庭成员")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 60)
        }
    }

    private var emptyTitle: String {
        if selectedCategoryName != "全部" {
            return "没有\(selectedCategoryName)"
        }
        switch viewModel.selectedFilter {
        case .all:
            return "衣橱还是空的"
        case .unassigned:
            return "没有未分配的衣物"
        case .member(let id):
            let name = viewModel.familyMembers.first(where: { $0.id == id })?.name ?? "该成员"
            return "还没有\(name)的衣服"
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Menu {
            Button {
                showCamera = true
            } label: {
                Label("拍照", systemImage: "camera")
            }
            Button {
                showPhotoPicker = true
            } label: {
                Label("从相册选择", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(AppColors.accent)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 3)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Loading Toast

    private var loadingToast: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.9)
            Text("正在处理服装...")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.78))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            TextField("搜索颜色、风格、类别...", text: $viewModel.searchText)
                .font(.system(size: 14))
                .onSubmit { UIApplication.dismissKeyboard() }
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(.systemGray3))
                }
            }
            Button("取消") {
                viewModel.searchText = ""
                showSearch = false
            }
            .font(.system(size: 14))
            .foregroundColor(AppColors.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    // MARK: - Toolbar Buttons

    private var searchButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSearch.toggle()
                if !showSearch { viewModel.searchText = "" }
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }

    private var trashButton: some View {
        Button { showDeletedItems = true } label: {
            Image(systemName: "trash")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Category Grid Sheet (查看全部)

struct CategoryGridSheet: View {
    let title: String
    let items: [ClothingItem]
    let idleItemIDs: Set<UUID>
    let onSelect: (ClothingItem) -> Void
    let onDelete: (ClothingItem) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var itemToDelete: ClothingItem? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        ClothingItemCard(
                            item: item,
                            isIdle: idleItemIDs.contains(item.id ?? UUID())
                        )
                        .frame(maxWidth: .infinity)
                        .onTapGesture {
                            onSelect(item)
                            dismiss()
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                itemToDelete = item
                            } label: {
                                Label("删除单品", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGray6).ignoresSafeArea())
            .navigationTitle("\(title) · \(items.count)件")
            .navigationBarTitleDisplayMode(.inline)
            .alert("确认删除？", isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            )) {
                Button("删除单品", role: .destructive) {
                    if let item = itemToDelete { onDelete(item) }
                    itemToDelete = nil
                }
                Button("取消", role: .cancel) { itemToDelete = nil }
            } message: {
                Text("删除后可在「已删除」中恢复")
            }
        }
    }
}

// MARK: - Deleted Items View

struct DeletedItemsView: View {
    @EnvironmentObject var viewModel: WardrobeViewModel
    @Environment(\.dismiss) var dismiss

    var deletedItems: [ClothingItem] {
        PersistenceController.shared.fetchClothingItems(includeDeleted: true).filter { $0.isSoftDeleted }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(deletedItems) { item in
                    HStack(spacing: 12) {
                        LocalImageView(path: item.flatLayImagePath ?? item.originalImagePath)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.subCategory ?? item.category ?? "未知")
                                .fontWeight(.medium)
                            Text(item.category ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("恢复") { viewModel.restore(item) }
                            .foregroundColor(AppColors.accent)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.permanentDelete(item)
                        } label: {
                            Label("永久删除", systemImage: "trash.fill")
                        }
                    }
                }
            }
            .navigationTitle("已删除")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
