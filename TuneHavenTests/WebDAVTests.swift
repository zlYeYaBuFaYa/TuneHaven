import Testing
import Foundation
@testable import TuneHaven

// MARK: - WebDAV XML Parser Tests

@Suite("WebDAVXMLParser Tests")
struct WebDAVXMLParserTests {

    private let sampleXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <d:multistatus xmlns:d="DAV:">
      <d:response>
        <d:href>/dav/Music/</d:href>
        <d:propstat>
          <d:prop>
            <d:displayname>Music</d:displayname>
            <d:resourcetype><d:collection/></d:resourcetype>
            <d:getlastmodified>Thu, 19 Mar 2026 08:00:00 GMT</d:getlastmodified>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/Music/subfolder/</d:href>
        <d:propstat>
          <d:prop>
            <d:displayname>subfolder</d:displayname>
            <d:resourcetype><d:collection/></d:resourcetype>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/Music/song.mp3</d:href>
        <d:propstat>
          <d:prop>
            <d:displayname>song.mp3</d:displayname>
            <d:getcontentlength>4398046</d:getcontentlength>
            <d:getcontenttype>audio/mpeg</d:getcontenttype>
            <d:getlastmodified>Wed, 18 Mar 2026 12:30:00 GMT</d:getlastmodified>
            <d:resourcetype/>
            <d:getetag>"abc123"</d:getetag>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/Music/album.flac</d:href>
        <d:propstat>
          <d:prop>
            <d:displayname>album.flac</d:displayname>
            <d:getcontentlength>28100000</d:getcontentlength>
            <d:getcontenttype>audio/flac</d:getcontenttype>
            <d:resourcetype/>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """

    @Test("解析过滤父目录条目")
    func testFilterParentDirectory() throws {
        let data = Data(sampleXML.utf8)
        let files = try WebDAVXMLParser.parseMultiStatus(data, requestPath: "/dav/Music/")
        #expect(files.count == 3)
        #expect(files.allSatisfy { $0.href != "/dav/Music/" })
    }

    @Test("正确解析目录条目")
    func testParseDirectory() throws {
        let data = Data(sampleXML.utf8)
        let files = try WebDAVXMLParser.parseMultiStatus(data, requestPath: "/dav/Music/")
        let dir = files.first { $0.displayName == "subfolder" }
        #expect(dir != nil)
        #expect(dir?.isDirectory == true)
    }

    @Test("正确解析文件属性")
    func testParseFileAttributes() throws {
        let data = Data(sampleXML.utf8)
        let files = try WebDAVXMLParser.parseMultiStatus(data, requestPath: "/dav/Music/")
        let song = files.first { $0.displayName == "song.mp3" }
        #expect(song != nil)
        #expect(song?.isDirectory == false)
        #expect(song?.contentLength == 4398046)
        #expect(song?.contentType == "audio/mpeg")
        #expect(song?.etag == "\"abc123\"")
        #expect(song?.lastModified != nil)
    }

    @Test("父目录带尾斜杠和不带尾斜杠都能过滤")
    func testFilterParentWithAndWithoutTrailingSlash() throws {
        let data = Data(sampleXML.utf8)
        let files1 = try WebDAVXMLParser.parseMultiStatus(data, requestPath: "/dav/Music")
        let files2 = try WebDAVXMLParser.parseMultiStatus(data, requestPath: "/dav/Music/")
        #expect(files1.count == 3)
        #expect(files2.count == 3)
    }

    @Test("空响应返回空数组")
    func testEmptyResponse() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:multistatus xmlns:d="DAV:">
        </d:multistatus>
        """
        let files = try WebDAVXMLParser.parseMultiStatus(Data(xml.utf8), requestPath: "/dav/")
        #expect(files.isEmpty)
    }

    @Test("中文路径 URL 编码的 href 能正确解析文件名")
    func testChinesePathDecoding() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/%E9%9F%B3%E4%B9%90/</d:href>
            <d:propstat>
              <d:prop><d:displayname>音乐</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/%E9%9F%B3%E4%B9%90/%E6%AD%8C%E6%9B%B2.mp3</d:href>
            <d:propstat>
              <d:prop><d:displayname></d:displayname><d:getcontentlength>1000</d:getcontentlength><d:resourcetype/></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
        let files = try WebDAVXMLParser.parseMultiStatus(Data(xml.utf8), requestPath: "/dav/音乐/")
        #expect(files.count == 1)
        #expect(files[0].fileName == "歌曲.mp3")
    }
}

// MARK: - WebDAVFile Tests

@Suite("WebDAVFile Tests")
struct WebDAVFileTests {

    @Test("isAudio 对支持格式返回 true")
    func testIsAudioSupported() {
        let extensions = ["mp3", "m4a", "aac", "alac", "wav", "flac", "aiff", "aif", "caf"]
        for ext in extensions {
            let file = WebDAVFile(href: "/test.\(ext)", displayName: "test.\(ext)",
                                  contentLength: 1000, contentType: nil, lastModified: nil,
                                  isDirectory: false, etag: nil)
            #expect(file.isAudio, "Expected \(ext) to be audio")
        }
    }

    @Test("isAudio 对不支持格式返回 false")
    func testIsAudioUnsupported() {
        let extensions = ["ogg", "opus", "wma", "txt", "jpg"]
        for ext in extensions {
            let file = WebDAVFile(href: "/test.\(ext)", displayName: "test.\(ext)",
                                  contentLength: 1000, contentType: nil, lastModified: nil,
                                  isDirectory: false, etag: nil)
            #expect(!file.isAudio, "Expected \(ext) to not be audio")
        }
    }

    @Test("目录的 isAudio 始终返回 false")
    func testDirectoryIsNotAudio() {
        let file = WebDAVFile(href: "/music.mp3/", displayName: "music.mp3",
                              contentLength: 0, contentType: nil, lastModified: nil,
                              isDirectory: true, etag: nil)
        #expect(!file.isAudio)
    }

    @Test("fileName 优先使用 displayName")
    func testFileNamePrefersDisplayName() {
        let file = WebDAVFile(href: "/path/encoded%20name.mp3", displayName: "real name.mp3",
                              contentLength: 0, contentType: nil, lastModified: nil,
                              isDirectory: false, etag: nil)
        #expect(file.fileName == "real name.mp3")
    }

    @Test("fileName 在 displayName 为空时从 href 解码")
    func testFileNameFallsBackToHref() {
        let file = WebDAVFile(href: "/path/%E6%AD%8C%E6%9B%B2.mp3", displayName: "",
                              contentLength: 0, contentType: nil, lastModified: nil,
                              isDirectory: false, etag: nil)
        #expect(file.fileName == "歌曲.mp3")
    }

    @Test("formattedSize 正确格式化")
    func testFormattedSize() {
        let file = WebDAVFile(href: "/test.mp3", displayName: "test.mp3",
                              contentLength: 4_398_046, contentType: nil, lastModified: nil,
                              isDirectory: false, etag: nil)
        #expect(!file.formattedSize.isEmpty)
    }
}

// MARK: - WebDAVAccount Tests

@Suite("WebDAVAccount Tests")
struct WebDAVAccountTests {

    @Test("effectiveDisplayName 优先使用自定义名称")
    func testEffectiveDisplayNameCustom() {
        let account = WebDAVAccount(displayName: "坚果云",
                                    serverURL: "https://dav.jianguoyun.com/dav/")
        #expect(account.effectiveDisplayName == "坚果云")
    }

    @Test("effectiveDisplayName 空名称时使用域名")
    func testEffectiveDisplayNameFallback() {
        let account = WebDAVAccount(displayName: "",
                                    serverURL: "https://dav.jianguoyun.com/dav/")
        #expect(account.effectiveDisplayName == "dav.jianguoyun.com")
    }

    @Test("host 从 serverURL 中提取")
    func testHostExtraction() {
        let account = WebDAVAccount(serverURL: "https://192.168.1.100:5006/webdav/")
        #expect(account.host == "192.168.1.100")
    }

    @Test("Codable 编解码一致")
    func testCodable() throws {
        let account = WebDAVAccount(displayName: "NAS", serverURL: "https://my.nas.local/dav/",
                                    username: "admin", trustSelfSignedCert: true)
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(WebDAVAccount.self, from: data)
        #expect(decoded.id == account.id)
        #expect(decoded.displayName == account.displayName)
        #expect(decoded.serverURL == account.serverURL)
        #expect(decoded.username == account.username)
        #expect(decoded.trustSelfSignedCert == account.trustSelfSignedCert)
    }
}

// MARK: - AppError WebDAV 错误码 Tests

@Suite("AppError WebDAV Tests")
struct AppErrorWebDAVTests {

    @Test("WebDAV 错误码正确")
    func testWebDAVErrorCodes() {
        #expect(AppError.webdavConnectionFailed("timeout").errorCode == "DAV001")
        #expect(AppError.webdavAuthFailed.errorCode == "DAV002")
        #expect(AppError.webdavServerNotSupported.errorCode == "DAV003")
        #expect(AppError.webdavDownloadFailed("song.mp3").errorCode == "DAV004")
        #expect(AppError.webdavCertificateError.errorCode == "DAV005")
    }

    @Test("WebDAV 错误描述非空")
    func testWebDAVErrorDescriptions() {
        #expect(AppError.webdavConnectionFailed("test").errorDescription != nil)
        #expect(AppError.webdavAuthFailed.errorDescription != nil)
        #expect(AppError.webdavServerNotSupported.errorDescription != nil)
        #expect(AppError.webdavDownloadFailed("test").errorDescription != nil)
        #expect(AppError.webdavCertificateError.errorDescription != nil)
    }

    @Test("WebDAV 错误码唯一性")
    func testWebDAVErrorCodesUnique() {
        let codes = [
            AppError.webdavConnectionFailed("").errorCode,
            AppError.webdavAuthFailed.errorCode,
            AppError.webdavServerNotSupported.errorCode,
            AppError.webdavDownloadFailed("").errorCode,
            AppError.webdavCertificateError.errorCode
        ]
        #expect(Set(codes).count == codes.count)
    }
}

// MARK: - WebDAVImportResult Tests

@Suite("WebDAVImportResult Tests")
struct WebDAVImportResultTests {

    @Test("totalSelected 正确计算")
    func testTotalSelected() {
        let result = WebDAVImportResult(downloadedCount: 3, downloadFailedCount: 1,
                                        skippedOversizeCount: 2, importResult: nil, errors: [])
        #expect(result.totalSelected == 6)
    }
}
