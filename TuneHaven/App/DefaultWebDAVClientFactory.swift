import Foundation

struct DefaultWebDAVClientFactory: WebDAVClientFactory {
    func makeClient(baseURL: URL, username: String, password: String, trustSelfSignedCert: Bool) -> WebDAVClientProtocol {
        WebDAVClient(configuration: .init(
            baseURL: baseURL,
            username: username,
            password: password,
            trustSelfSignedCert: trustSelfSignedCert
        ))
    }
}
