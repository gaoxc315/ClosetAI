import SwiftUI

struct FamilyMemberBar: View {
    @EnvironmentObject var viewModel: WardrobeViewModel
    var showsUnassigned: Bool = true
    var showsManage: Bool = true
    var onManage: () -> Void = {}

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", selected: viewModel.selectedFilter == .all) {
                    viewModel.selectFilter(.all)
                }
                ForEach(viewModel.familyMembers) { member in
                    if let id = member.id {
                        chip(
                            title: member.name ?? "成员",
                            selected: viewModel.selectedFilter == .member(id)
                        ) {
                            viewModel.selectFilter(.member(id))
                        }
                    }
                }
                if showsUnassigned {
                    chip(title: "未分配", selected: viewModel.selectedFilter == .unassigned) {
                        viewModel.selectFilter(.unassigned)
                    }
                }
                if showsManage {
                    Button(action: onManage) {
                        Label("管理", systemImage: "person.badge.plus")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(.systemGray6))
                            .foregroundColor(AppColors.accent)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? AppColors.accent : Color(.systemGray6))
                .foregroundColor(selected ? .white : .primary)
                .clipShape(Capsule())
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
