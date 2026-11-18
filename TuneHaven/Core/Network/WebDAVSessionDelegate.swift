import CryptoKit
import Foundation
import Security

/// @unchecked Sendable: policy 为 let 常量；rejectedChangedCertificate 由锁保护。
final class WebDAVSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let policy: WebDAVTrustPolicy
    private let lock = NSLock()
    private var _rejectedChangedCertificate = false

    /// 是否因证书与记住的指纹不符而拒绝过连接，客户端据此给出明确错误
    var rejectedChangedCertificate: Bool { lock.withLock { _rejectedChangedCertificate } }

    init(policy: WebDAVTrustPolicy) {
        self.policy = policy
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let systemTrusted = SecTrustEvaluateWithError(trust, nil)
        switch policy.decide(systemTrusted: systemTrusted, presented: Self.leafFingerprint(trust)) {
        case .defaultHandling:
            completionHandler(.performDefaultHandling, nil)
        case .accept:
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .acceptAndPin(let fingerprint):
            policy.onPinned?(fingerprint)
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .rejectChanged:
            lock.withLock { _rejectedChangedCertificate = true }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    static func leafFingerprint(_ trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        return fingerprint(of: SecCertificateCopyData(leaf) as Data)
    }

    static func fingerprint(of certificateDER: Data) -> String {
        SHA256.hash(data: certificateDER).map { String(format: "%02x", $0) }.joined()
    }
}
