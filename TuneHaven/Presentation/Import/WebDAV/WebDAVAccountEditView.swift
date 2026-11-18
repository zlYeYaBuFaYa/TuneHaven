import SwiftUI

struct WebDAVAccountEditView: View {
    enum Mode: Identifiable {
        case add
        case edit(WebDAVAccount)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let a): return a.id.uuidString
            }
        }
    }

    @EnvironmentObject private var webDAVService: WebDAVService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var displayName = ""
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var trustSelfSignedCert = false

    @State private var isTesting = false
    @State private var testResult: TestResult?

    private enum TestResult {
        case success
        case failure(String)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var title: String { isEditing ? "编辑 WebDAV" : "添加 WebDAV" }

    private var trimmedServerURL: String { serverURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedServerURL.isEmpty &&
        !trimmedUsername.isEmpty &&
        !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FlowIntro(symbol: "externaldrive.badge.wifi", title: "保存一个音乐来源", message: "填写服务器地址和登录信息。密码安全保存在本机钥匙串中。")
                        .plainListRow()
                }
                serverConfigSection
                advancedSection
                testConnectionSection
                presetSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .foregroundColor(palette.accent)
                        .disabled(!canSave || isTesting || isHTTPPublicAddress)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    // MARK: - Sections

    private var serverConfigSection: some View {
        Section {
            HStack {
                Text("显示名称")
                    .foregroundColor(palette.textPrimary)
                TextField("可选，如「坚果云」", text: $displayName)
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .importRowSurface()

            HStack {
                Text("服务器地址")
                    .foregroundColor(palette.textPrimary)
                TextField("https://dav.example.com/dav/", text: $serverURL)
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            .importRowSurface()

            if isHTTPPublicAddress {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(SemanticColor.danger)
                        .font(.caption)
                    Text("公网地址必须使用 HTTPS，HTTP 仅支持局域网")
                        .font(.caption)
                        .foregroundColor(SemanticColor.danger)
                }
                .importRowSurface(secondary: true)
            } else if isHTTPAddress {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(SemanticColor.warning)
                        .font(.caption)
                    Text("HTTP 连接不加密，密码和文件将以明文传输")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                .importRowSurface(secondary: true)
            }

            HStack {
                Text("用户名")
                    .foregroundColor(palette.textPrimary)
                TextField("user@example.com", text: $username)
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .importRowSurface()

            HStack {
                Text("密码")
                    .foregroundColor(palette.textPrimary)
                SecureField("应用密码", text: $password)
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .importRowSurface()
        } header: {
            Text("服务器配置")
                .foregroundColor(palette.textSecondary)
        }
    }

    private var advancedSection: some View {
        Section {
            Toggle(isOn: $trustSelfSignedCert) {
                Text("信任自签证书")
                    .foregroundColor(palette.textPrimary)
            }
            .tint(palette.accent)
            .importRowSurface()
        } header: {
            Text("高级选项")
                .foregroundColor(palette.textSecondary)
        } footer: {
            if trustSelfSignedCert {
                Text("首次连接时记住服务器证书，之后证书变化会拒绝连接。确认服务器可信后重新保存账户，即可信任新证书。")
                    .foregroundColor(palette.textSecondary)
            }
        }
    }

    private var testConnectionSection: some View {
        Section {
            Button {
                testConnection()
            } label: {
                HStack {
                    Spacer()
                    if isTesting {
                        ProgressView()
                            .tint(palette.accent)
                        Text("测试中...")
                            .foregroundColor(palette.textSecondary)
                    } else {
                        Text("测试连接")
                            .foregroundColor(canSave ? palette.accent : palette.textSecondary)
                    }
                    Spacer()
                }
            }
            .disabled(!canSave || isTesting)
            .importRowSurface()

            if let result = testResult {
                switch result {
                case .success:
                    Label("连接成功", systemImage: "checkmark.circle.fill")
                        .foregroundColor(SemanticColor.success)
                        .font(.subheadline)
                        .importRowSurface()
                case .failure(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .foregroundColor(SemanticColor.danger)
                        .font(.subheadline)
                        .importRowSurface()
                }
            }
        }
    }

    private var presetSection: some View {
        Section {
            presetRow("坚果云", url: "https://dav.jianguoyun.com/dav/")
            presetRow("Alist", url: "http://IP:5244/dav/")
            presetRow("群晖 NAS", url: "https://IP:5006/")
            presetRow("InfiniCLOUD", url: "https://xxx.teracloud.jp/dav/")
        } header: {
            Text("常用 WebDAV 地址")
                .foregroundColor(palette.textSecondary)
        }
    }

    private func presetRow(_ name: String, url: String) -> some View {
        Button {
            serverURL = url
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(palette.textPrimary)
                Text(url)
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
        }
        .importRowSurface()
    }

    // MARK: - Logic

    private var isHTTPAddress: Bool {
        serverURL.lowercased().hasPrefix("http://")
    }

    private var isHTTPPublicAddress: Bool {
        guard isHTTPAddress else { return false }
        guard let url = URL(string: serverURL), let host = url.host else { return false }
        return !isLocalNetwork(host: host)
    }

    private func isLocalNetwork(host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower == "127.0.0.1" || lower == "::1" { return true }
        if lower.hasSuffix(".local") { return true }
        if lower.hasPrefix("fe80:") || lower.hasPrefix("fd") || lower.hasPrefix("fc") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        return false
    }

    private func loadExisting() {
        if case .edit(let account) = mode {
            displayName = account.displayName
            serverURL = account.serverURL
            username = account.username
            trustSelfSignedCert = account.trustSelfSignedCert
            password = webDAVService.password(for: account.id) ?? ""
        }
    }

    private func testConnection() {
        guard canSave else { return }
        isTesting = true
        testResult = nil

        let account = WebDAVAccount(
            displayName: displayName, serverURL: trimmedServerURL,
            username: trimmedUsername,
            trustSelfSignedCert: trustSelfSignedCert
        )
        Task {
            do {
                _ = try await webDAVService.testConnection(account: account, password: password)
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func save() {
        guard canSave else { return }
        guard !isHTTPPublicAddress else {
            testResult = .failure("公网地址必须使用 HTTPS，请将地址改为 https:// 开头")
            return
        }

        let account: WebDAVAccount
        if case .edit(let existing) = mode {
            account = WebDAVAccount(
                id: existing.id, displayName: displayName,
                serverURL: trimmedServerURL,
                username: trimmedUsername,
                trustSelfSignedCert: trustSelfSignedCert,
                createdAt: existing.createdAt, lastConnectedAt: existing.lastConnectedAt
            )
        } else {
            account = WebDAVAccount(
                displayName: displayName,
                serverURL: trimmedServerURL,
                username: trimmedUsername,
                trustSelfSignedCert: trustSelfSignedCert
            )
        }

        do {
            if isEditing {
                try webDAVService.updateAccount(account, password: password)
            } else {
                try webDAVService.addAccount(account, password: password)
            }
            dismiss()
        } catch {
            testResult = .failure("保存失败: \(error.localizedDescription)")
        }
    }
}
