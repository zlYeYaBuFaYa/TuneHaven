import Foundation

struct DefaultWebDAVClientFactory: WebDAVClientFactory {
    func makeClient(baseURL: URL, username: String, password: String, trust: WebDAVTrustPolicy) -> WebDAVClientProtocol {
        WebDAVClient(configuration: .init(
            baseURL: baseURL,
            username: username,
            password: password,
            trust: trust
        ))
    }
}
