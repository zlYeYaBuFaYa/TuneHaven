import Testing
@testable import TuneHaven

@Suite("WiFi 上传令牌")
struct WiFiTransferSessionTests {

    @Test("密码关闭时，没有请求头也允许上传")
    func testPasswordOffAllowsUpload() {
        var session = WiFiTransferSession()
        session.passwordEnabled = false
        #expect(session.allowsUpload(authorizationHeader: nil))
    }

    @Test("密码开启但尚未签发 token 时拒绝上传")
    func testPasswordOnWithoutTokenDenies() {
        var session = WiFiTransferSession()
        session.passwordEnabled = true
        #expect(session.allowsUpload(authorizationHeader: "Bearer anything") == false)
    }

    @Test("正确的 Bearer token 允许上传，错误前缀或错误 token 拒绝")
    func testBearerToken() {
        var session = WiFiTransferSession()
        session.passwordEnabled = true
        let token = session.issueUploadToken()

        #expect(session.allowsUpload(authorizationHeader: "Bearer \(token)"))
        #expect(session.allowsUpload(authorizationHeader: token) == false)
        #expect(session.allowsUpload(authorizationHeader: "Bearer other") == false)
        #expect(session.allowsUpload(authorizationHeader: nil) == false)
    }

    @Test("作废后原来的 token 不能再上传")
    func testInvalidateToken() {
        var session = WiFiTransferSession()
        session.passwordEnabled = true
        let token = session.issueUploadToken()
        session.invalidateUploadToken()
        #expect(session.allowsUpload(authorizationHeader: "Bearer \(token)") == false)
    }
}
