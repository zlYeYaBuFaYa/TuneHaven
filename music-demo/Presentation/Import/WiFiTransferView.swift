import SwiftUI

struct WiFiTransferView: View {
    @EnvironmentObject private var importService: ImportService
    @EnvironmentObject private var libraryService: MusicLibraryService
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @StateObject private var server = WiFiTransferServer()
    @State private var passwordEnabled = true
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var receivedFiles: [String] = []

    var body: some View {
        NavigationStack {
            List {
                serverStatusSection
                if server.isRunning {
                    connectionInfoSection
                }
                if !receivedFiles.isEmpty {
                    receivedSection
                }
                securitySection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .adaptiveBackground()
            .navigationTitle("WiFi 传输")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        server.stop()
                        dismiss()
                    }
                    .foregroundColor(palette.primary)
                }
            }
        }
        .onDisappear { server.stop() }
        .onChange(of: server.securityAlert) { _, alert in
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
            .tint(palette.primary)
            .listRowBackground(palette.surface)

            if !server.isRunning {
                Toggle("启用密码保护", isOn: $passwordEnabled)
                    .foregroundColor(palette.textPrimary)
                    .tint(palette.primary)
                    .listRowBackground(palette.surface)
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
                // 二维码（TDD Section 7.2）
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        QRCodeView(content: address, size: 160)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.15), radius: 6)
                        Text("用手机/电脑扫码访问")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(palette.surface)

                VStack(alignment: .leading, spacing: 8) {
                    Text("电脑访问地址")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                    Text(address)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(palette.primary)
                        .onTapGesture {
                            UIPasteboard.general.string = address
                        }
                    Text("点击复制地址")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
                .listRowBackground(palette.surface)
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
                            .foregroundColor(palette.primary)
                    }
                }
                .listRowBackground(palette.surface)
            }
        } header: {
            Text("连接信息")
                .foregroundColor(palette.textSecondary)
        } footer: {
            Text("确保手机和电脑在同一 WiFi 网络下，在电脑浏览器中输入以上地址后上传音乐文件。")
                .foregroundColor(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var receivedSection: some View {
        Section("已接收 \(receivedFiles.count) 个文件") {
            ForEach(receivedFiles, id: \.self) { file in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(palette.primary)
                    Text(file)
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                }
                .listRowBackground(palette.surface)
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
            .listRowBackground(palette.surfaceSecondary)
        }
    }

    private func tryStart() {
        do {
            try server.start(passwordEnabled: passwordEnabled)
            server.onFileReceived = { filename, url in
                receivedFiles.append(filename)
                Task { [url] in
                    let result = await importService.processWiFiFile(tempURL: url, originalFilename: filename)
                    if result.status == .success || result.status == .successIncompleteMetadata {
                        await libraryService.loadSongs()
                    }
                }
            }
        } catch {
            alertMessage = "服务启动失败：\(error.localizedDescription)"
            showAlert = true
        }
    }
}
