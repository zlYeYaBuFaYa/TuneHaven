import Foundation

/// @unchecked Sendable: trustSelfSignedCert 为 let 常量，初始化后不可变，
/// 但编译器无法自动推断 NSObject 子类的 Sendable 安全性，故需手动标注。
final class WebDAVSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let trustSelfSignedCert: Bool

    init(trustSelfSignedCert: Bool = false) {
        self.trustSelfSignedCert = trustSelfSignedCert
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           trustSelfSignedCert,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
