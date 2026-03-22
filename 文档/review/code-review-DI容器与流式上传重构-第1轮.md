# 代码 Review：DI 容器与流式上传重构 - 第 1 轮

> 日期：2026-03-22 | 类型：AI 自审 | 范围：9 个文件

## 结论：不通过

| 维度 | 结论 | 说明 |
|------|------|------|
| 逻辑正确性 | ⚠️ | bodyReadLoop 连接错误时仍尝试处理不完整上传 |
| 错误处理 | ⚠️ | 上传连接断开后的清理路径不完整 |
| 安全 | ✅ | 无新增安全问题 |
| 线程安全 | ✅ | @MainActor 一致，StreamingUploadContext @unchecked Sendable 合理 |
| 架构合规 | ✅ | DI 容器在 App 层，依赖方向正确 |
| 代码风格 | ✅ | MARK 分组清晰，命名一致 |
| API 设计 | ✅ | 公开接口不变，内部方法语义清晰 |
| 性能 | ✅ | mmap + 直写优化，内存峰值可控 |
| 内存管理 | ✅ | [weak self] 一致，FileHandle 正确 closeFile |
| 可维护性 | ✅ | DI 容器集中管理，两阶段解析职责清晰 |

## 问题

### 🟡 建议问题

#### 1. bodyReadLoop — 连接错误时不应处理不完整文件

当前代码：

```swift
if isComplete || error != nil || context.bytesReceived >= context.contentLength {
    context.fileHandle.closeFile()
    self.processUploadedTempFile(context: context, connection: connection)
}
```

`error != nil` 时（如连接中断），文件可能不完整，`processUploadedTempFile` 会尝试解析截断的 multipart 数据。虽然 `parseMultipart` 最终会返回"未找到文件"错误，但浪费了 mmap 加载和解析步骤。

**建议**：错误时直接清理，不进入解析：

```swift
if error != nil {
    context.fileHandle.closeFile()
    try? FileManager.default.removeItem(at: context.tempFileURL)
    self.transferProgress = nil
    self.connectionState = .idle
    return
}
if isComplete || context.bytesReceived >= context.contentLength {
    context.fileHandle.closeFile()
    self.processUploadedTempFile(context: context, connection: connection)
}
```

### 🟢 优化问题

#### 2. beginStreamingUpload — connectionState 丢失 IP

`beginStreamingUpload` 中设置 `connectionState = .transferring(ip: "")`，丢失了 `handleNewConnection` 中设定的客户端 IP。

**建议**：将 `receiveHTTPRequest` 的 `ip` 参数传递到 `beginStreamingUpload`：

```swift
private func beginStreamingUpload(headers: Data, ip: String) -> StreamingUploadContext? {
    // ...
    connectionState = .transferring(ip: ip)
    // ...
}
```

调用处改为：`self.beginStreamingUpload(headers: Data(headers), ip: ip)`

#### 3. TuneHavenApp — `import AVFoundation` 可能多余

重构后 `TuneHavenApp` 不再直接使用 AVFoundation 类型，`import AVFoundation` 可以移除。

## 修改计划

1. WiFiTransferServer.bodyReadLoop：分离错误处理和正常完成逻辑
2. WiFiTransferServer.beginStreamingUpload：添加 ip 参数
3. TuneHavenApp：移除 `import AVFoundation`
