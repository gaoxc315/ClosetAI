import SwiftUI

struct FamilyMemberBar: View {
    @EnvironmentObject var viewModel: WardrobeViewModel
    var showsUnassigned: Bool = true
    var showsManage: Bool = true
    var onManage: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            MagnifyingTabBar(
                items: magnifyItems,
                axis: .horizontal,
                selection: selectionBinding,
                onSelect: handleSelect
            )
            .frame(height: 56)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .zIndex(2)
    }

    private var magnifyItems: [MagnifyingTabItem] {
        var items = [MagnifyingTabItem(id: "all", icon: "square.grid.2x2", title: "全部")]
        for member in viewModel.familyMembers {
            if let id = member.id {
                items.append(MagnifyingTabItem(id: id.uuidString, icon: "person", title: member.name ?? "成员"))
            }
        }
        if showsUnassigned {
            items.append(MagnifyingTabItem(id: "unassigned", icon: "tray", title: "未分配"))
        }
        if showsManage {
            items.append(MagnifyingTabItem(id: "manage", icon: "person.badge.plus", title: "管理", isAction: true))
        }
        return items
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: {
                switch viewModel.selectedFilter {
                case .all: return "all"
                case .unassigned: return "unassigned"
                case .member(let id): return id.uuidString
                }
            },
            set: { newValue in
                applySelection(newValue)
            }
        )
    }

    private func handleSelect(_ item: MagnifyingTabItem) {
        if item.isAction {
            onManage()
            return
        }
        applySelection(item.id)
    }

    private func applySelection(_ id: String) {
        switch id {
        case "all":
            viewModel.selectFilter(.all)
        case "unassigned":
            viewModel.selectFilter(.unassigned)
        default:
            if let uuid = UUID(uuidString: id) {
                viewModel.selectFilter(.member(uuid))
            }
        }
    }
}

struct ManageFamilyMembersView: View {
    @EnvironmentObject var viewModel: WardrobeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var newName = ""
    @State private var memberToDelete: FamilyMember?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("例如：妈妈、爸爸、孩子", text: $newName)
                        Button("添加") {
                            viewModel.addFamilyMember(name: newName)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("新增成员")
                }

                Section {
                    ForEach(viewModel.familyMembers) { member in
                        HStack {
                            TextField("姓名", text: Binding(
                                get: { member.name ?? "" },
                                set: { viewModel.renameFamilyMember(member, name: $0) }
                            ))
                            Text(countText(for: member))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                memberToDelete = member
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("家庭成员")
                } footer: {
                    Text("删除成员后，其衣物会回到「未分配」，不会被删除。")
                }
            }
            .navigationTitle("家庭成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("删除该成员？", isPresented: Binding(
                get: { memberToDelete != nil },
                set: { if !$0 { memberToDelete = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let member = memberToDelete {
                        viewModel.deleteFamilyMember(member)
                    }
                    memberToDelete = nil
                }
                Button("取消", role: .cancel) { memberToDelete = nil }
            } message: {
                Text("衣物会保留，并移到「未分配」。")
            }
        }
    }

    private func countText(for member: FamilyMember) -> String {
        let count = viewModel.items.filter { !$0.isSoftDeleted && $0.memberId == member.id }.count
        return "\(count) 件"
    }
}

struct AssignMemberSheet: View {
    @EnvironmentObject var viewModel: WardrobeViewModel
    let onPick: (UUID?) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onPick(nil)
                    dismiss()
                } label: {
                    Text("暂不分配")
                }

                ForEach(viewModel.familyMembers) { member in
                    Button {
                        onPick(member.id)
                        dismiss()
                    } label: {
                        Text(member.name ?? "成员")
                    }
                }
            }
            .navigationTitle("这件衣服属于谁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
