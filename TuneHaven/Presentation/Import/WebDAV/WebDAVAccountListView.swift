import SwiftUI

struct WebDAVAccountListView: View {
    @EnvironmentObject private var webDAVService: WebDAVService
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var showAddAccount = false
    @State private var editingAccount: WebDAVAccount?
    @State private var navigateToAccount: WebDAVAccount?

    var body: some View {
        NavigationStack {
            List {
                if webDAVService.accounts.isEmpty {
                    emptySection
                } else {
                    accountsSection
                }
                guideSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("WebDAV 导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddAccount = true } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundColor(palette.primary)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { navigateToAccount != nil },
                set: { if !$0 { navigateToAccount = nil } }
            )) {
                if let account = navigateToAccount {
                    WebDAVBrowserView(account: account)
                }
            }
            .sheet(isPresented: $showAddAccount) {
                WebDAVAccountEditView(mode: .add)
            }
            .sheet(item: $editingAccount) { account in
                WebDAVAccountEditView(mode: .edit(account))
            }
            .onAppear { webDAVService.loadAccounts() }
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 40))
                    .foregroundColor(palette.textTertiary)
                Text("暂无 WebDAV 服务器")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Text("点击右上角 + 添加")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(palette.surface)
        }
    }

    private var accountsSection: some View {
        Section {
            ForEach(webDAVService.accounts) { account in
                accountRow(account)
            }
            .onDelete { indices in
                let validIndices = indices.filter { $0 < webDAVService.accounts.count }
                for index in validIndices {
                    try? webDAVService.deleteAccount(id: webDAVService.accounts[index].id)
                }
            }
        } header: {
            Text("WebDAV 服务器")
                .foregroundColor(palette.textSecondary)
        }
    }

    private func accountRow(_ account: WebDAVAccount) -> some View {
        Button {
            navigateToAccount = account
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundColor(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.primary))

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.effectiveDisplayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(palette.textPrimary)
                    Text(account.host)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                    if let lastConnected = account.lastConnectedAt {
                        Text("上次连接: \(lastConnected.relativeDescription)")
                            .font(.caption2)
                            .foregroundColor(palette.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(palette.surface)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                try? webDAVService.deleteAccount(id: account.id)
            } label: { Label("删除", systemImage: "trash") }

            Button { editingAccount = account } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(palette.primary)
        }
    }

    private var guideSection: some View {
        Section {
            StepGuideRow(step: "1", text: "点击右上角 + 添加 WebDAV 服务器")
            StepGuideRow(step: "2", text: "输入服务器地址和登录凭据")
            StepGuideRow(step: "3", text: "测试连接成功后保存")
            StepGuideRow(step: "4", text: "点击已添加的服务器浏览和导入")

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(SemanticColor.warning)
                    .font(.caption)
                Text("百度网盘不支持 WebDAV，需通过 Alist 等工具桥接后使用")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            .listRowBackground(palette.surfaceSecondary)
        } header: {
            Text("使用说明")
                .foregroundColor(palette.textSecondary)
        }
    }

}

