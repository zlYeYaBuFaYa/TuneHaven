import Foundation

/// URLProtocol 桩：按 URL 路径返回固定响应，可设延迟和响应头。
/// 用法：`URLSessionConfiguration.protocolClasses = [StubURLProtocol.self]`，各测试用不同路径避免互相影响。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status: Int = 200
        var body = Data()
        var headers: [String: String] = [:]
        var delay: TimeInterval = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]

    static func set(_ response: Response, for path: String) {
        lock.lock(); defer { lock.unlock() }
        responses[path] = response
    }

    private static func response(for path: String) -> Response? {
        lock.lock(); defer { lock.unlock() }
        return responses[path]
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    private var workItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let stub = Self.response(for: path) ?? Response(status: 404)
        let item = DispatchWorkItem { [weak self] in
            guard let self, let url = self.request.url else { return }
            var headers = stub.headers
            headers["Content-Length"] = "\(stub.body.count)"
            guard let http = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                             headerFields: headers) else { return }
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: stub.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        workItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay, execute: item)
    }

    override func stopLoading() {
        workItem?.cancel()
    }
}
