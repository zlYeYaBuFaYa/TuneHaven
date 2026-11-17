import SwiftUI

struct WiFiTransferView: View {
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @StateObject private var server = WiFiTransferServer()
    @AppStorage(AppStorageKey.wifiPasswordEnabled) private var passwordEnabled = true
    @State private var showAlert = false
    @State private var didCopyAddress = false
    @State private var alertMessage = ""
    @StateObject private var importQueue = WiFiImportQueue()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ImportIntro(symbol: "wifi", title: "让电脑里的音乐，来到手机", message: "手机和电脑连接同一 WiFi 后，开启服务并在电脑浏览器上传文件。")
                        .plainListRow()
                }
                serverStatusSection
                if server.isRunning {
                    connectionInfoSection
                }
                if !importQueue.items.isEmpty {
                    receivedSection
                }
                securitySection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("WiFi 传输")
            .navigationBarTitleDisplayMode(.inline)
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }
            }
        }
        .onDisappear {
            if server.isRunning { server.stop() }
        }
        .onChange(of: server.securityAlert) { alert in
            if let alert {
                switch alert {
                case .bruteForceDetected:
                    alertMessage = "检测到多次密码错误，已暂时禁用访问"
                    showAlert = true
                case .newDeviceWhileTransferring(let ip):
                    alertMessage = "新设备 \(ip) 尝试在传输中连接，已被拒绝"
                    showAlert = true
                case .unknownDeviceAttempt(let ip):
                    alertMessage = "未知设备 \(ip) 尝试连接"
                    showAlert = true
                }
            }
        }
        .alert("安全提醒", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var serverStatusSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { server.isRunning },
                set: { on in
                    if on { tryStart() } else { server.stop() }
                }
            )) {
                Label(server.isRunning ? "传输服务已开启" : "开启传输服务",
                      systemImage: "wifi.circle")
                    .foregroundColor(palette.textPrimary)
            }
            .tint(palette.accent)
            .importRowSurface()

            if !server.isRunning {
                Toggle("启用密码保护", isOn: $passwordEnabled)
                    .foregroundColor(palette.textPrimary)
                    .tint(palette.accent)
                    .importRowSurface()
            }
        } header: {
            Text("服务状态")
                .foregroundColor(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var connectionInfoSection: some View {
        Section {
            if let address = server.serverAddress {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        QRCodeView(content: address, size: 160)
                            .cornerRadius(8)
                            .shadow(color: palette.cardShadow, radius: 6)
                        Text("用手机/电脑扫码访问")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .importRowSurface()

                VStack(alignment: .leading, spacing: 8) {
                    Text("电脑访问地址")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                    Button {
                        UIPasteboard.general.string = address
                        didCopyAddress = true
                    } label: {
                        Label(address, systemImage: didCopyAddress ? "checkmark" : "doc.on.doc")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(palette.accent)
                            .frame(minHeight: 44)
                            .multilineTextAlignment(.leading)
                    }
                    .accessibilityLabel(didCopyAddress ? "地址已复制" : "复制电脑访问地址")
                    Text(didCopyAddress ? "地址已复制" : "点击复制地址")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                .importRowSurface()
            }
            if passwordEnabled, let pwd = server.password {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("访问密码")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                        Text(pwd)
                            .font(.system(.title2, design: .monospaced).bold())
                            .foregroundColor(palette.textPrimary)
                            .tracking(8)
                    }
                    Spacer()
                    Button {
                        _ = server.regeneratePassword()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(palette.accent)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("重新生成访问密码")
                }
                .importRowSurface()
            }
        } header: {
            Text("连接信息")
                .foregroundColor(palette.textSecondary)
        } footer: {
            Text("确保手机和电脑在同一 WiFi 网络下，在电脑浏览器中输入以上地址后上传音乐文件。")
                .foregroundColor(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var receivedSection: some View {
        Section("已接收 \(importQueue.items.count) 个文件") {
            ForEach(importQueue.items) { item in
                HStack(spacing: 10) {
                    statusIcon(item.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)
                        Text(statusText(item.status))
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                            .lineLimit(2)
                    }
                }
                .importRowSurface()
            }
        }
    }

    private var securitySection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield")
                    .foregroundColor(SemanticColor.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("安全提示")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                    Text("WiFi 传输使用 HTTP 协议，数据可能被同一局域网中的其他设备监听。请仅在可信网络环境中使用，建议开启密码保护。")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            }
            .importRowSurface(secondary: true)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: WiFiImportQueue.Status) -> some View {
        switch status {
        case .waiting:
            Image(systemName: "clock")
                .foregroundColor(palette.textSecondary)
        case .importing:
            ProgressView()
                .controlSize(.small)
        case .imported:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(palette.accent)
        case .duplicate:
            Image(systemName: "equal.circle.fill")
                .foregroundColor(palette.textSecondary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(SemanticColor.warning)
        }
    }

    private func statusText(_ status: WiFiImportQueue.Status) -> String {
        switch status {
        case .waiting: return "等待导入"
        case .importing: return "正在导入"
        case .imported: return "已导入"
        case .duplicate: return "曲库中已存在"
        case .failed(let reason): return "导入失败：\(reason)"
        }
    }

    private func tryStart() {
        let libraryService = libraryService
        importQueue.configure(importer: importService) {
            await libraryService.loadSongs()
        }
        let queue = importQueue
        server.onFileReceived = { filename, url in
            queue.enqueue(fileURL: url, originalFilename: filename)
        }
        do {
            try server.start(passwordEnabled: passwordEnabled)
        } catch {
            alertMessage = "服务启动失败：\(error.localizedDescription)"
            showAlert = true
        }
    }
}
