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
                Section {
                    FlowIntro(symbol: "server.rack", title: "连接你的私人音乐收藏", message: "添加 NAS 或 WebDAV 服务器，再选择需要保存到本机的音乐。")
                        .plainListRow()
                }
                if webDAVService.accounts.isEmpty {
                    emptySection
                } else {
                    accountsSection
                }
                guideSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("WebDAV 导入")
            .navigationBarTitleDisplayMode(.inline)
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddAccount = true } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("添加 WebDAV 服务器")
                    .foregroundColor(palette.accent)
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
                    .foregroundColor(palette.textSecondary)
                Text("暂无 WebDAV 服务器")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Button("添加服务器") { showAddAccount = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.onAction)
                    .padding(.horizontal, 20).frame(minHeight: 44)
                    .background(palette.actionFill, in: Capsule())
                Text("也可以从右上角添加")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .importRowSurface()
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
                PrimaryIconChip(systemName: "server.rack")

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
                            .foregroundColor(palette.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            .padding(.vertical, 4)
        }
        .importRowSurface()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                try? webDAVService.deleteAccount(id: account.id)
            } label: { Label("删除", systemImage: "trash") }

            Button { editingAccount = account } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(palette.accent)
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
            .importRowSurface(secondary: true)
        } header: {
            Text("使用说明")
                .foregroundColor(palette.textSecondary)
        }
    }

}

