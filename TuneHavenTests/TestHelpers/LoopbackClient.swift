import Foundation
import Network

/// 最小 TCP 客户端：手动控制读取节奏，用来制造传输中途的状态。
final class LoopbackClient: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "LoopbackClient")

    init(port: UInt16) {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error), .waiting(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func send(_ text: String) async {
        await withCheckedContinuation { continuation in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in continuation.resume() })
        }
    }

    /// 返回 nil 表示服务端已关闭连接。
    func receive() async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete || error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    func receiveAll() async -> Data {
        var all = Data()
        while let chunk = await receive() { all.append(chunk) }
        return all
    }

    /// 读到服务端关闭为止；超时仍未关闭返回 nil。
    func receiveUntilClosed(timeout: Duration = .seconds(2)) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask { await self.receiveAll() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            connection.cancel()
            group.cancelAll()
            return first
        }
    }

    deinit { connection.cancel() }
}
