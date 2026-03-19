import Foundation

final class WebDAVXMLParser: NSObject, XMLParserDelegate {

    static func parseMultiStatus(_ data: Data, requestPath: String) throws -> [WebDAVFile] {
        let parser = WebDAVXMLParser()
        return try parser.parse(data: data, requestPath: requestPath)
    }

    private var results: [WebDAVFile] = []
    private var requestPath = ""

    private var currentHref = ""
    private var currentDisplayName = ""
    private var currentContentLength: Int64 = 0
    private var currentContentType: String?
    private var currentLastModified: Date?
    private var currentIsDirectory = false
    private var currentEtag: String?

    private var currentElement = ""
    private var textBuffer = ""
    private var insideResponse = false
    private var insidePropstat = false
    private var insideProp = false
    private var insideResourceType = false

    private static let rfc1123Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    private func parse(data: Data, requestPath: String) throws -> [WebDAVFile] {
        self.requestPath = requestPath.removingPercentEncoding ?? requestPath
        results = []

        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.shouldProcessNamespaces = true
        xmlParser.parse()

        if let error = xmlParser.parserError {
            throw error
        }
        return results
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let local = localName(elementName)
        currentElement = local

        switch local {
        case "response":
            insideResponse = true
            resetCurrentEntry()
        case "propstat":
            insidePropstat = true
        case "prop":
            if insidePropstat { insideProp = true }
        case "resourcetype":
            if insideProp { insideResourceType = true }
        case "collection":
            if insideResourceType { currentIsDirectory = true }
        default:
            break
        }
        textBuffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let local = localName(elementName)
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch local {
        case "href":
            if insideResponse { currentHref = text }
        case "displayname":
            if insideProp { currentDisplayName = text }
        case "getcontentlength":
            if insideProp { currentContentLength = Int64(text) ?? 0 }
        case "getcontenttype":
            if insideProp { currentContentType = text.isEmpty ? nil : text }
        case "getlastmodified":
            if insideProp { currentLastModified = Self.rfc1123Formatter.date(from: text) }
        case "getetag":
            if insideProp { currentEtag = text.isEmpty ? nil : text }
        case "resourcetype":
            insideResourceType = false
        case "prop":
            insideProp = false
        case "propstat":
            insidePropstat = false
        case "response":
            insideResponse = false
            let decodedHref = currentHref.removingPercentEncoding ?? currentHref
            let decodedRequest = requestPath
            let isParent = decodedHref == decodedRequest
                || decodedHref == decodedRequest + "/"
                || decodedHref + "/" == decodedRequest
            if !isParent && !currentHref.isEmpty {
                let file = WebDAVFile(
                    href: currentHref,
                    displayName: currentDisplayName,
                    contentLength: currentContentLength,
                    contentType: currentContentType,
                    lastModified: currentLastModified,
                    isDirectory: currentIsDirectory,
                    etag: currentEtag
                )
                results.append(file)
            }
        default:
            break
        }
    }

    private func resetCurrentEntry() {
        currentHref = ""
        currentDisplayName = ""
        currentContentLength = 0
        currentContentType = nil
        currentLastModified = nil
        currentIsDirectory = false
        currentEtag = nil
    }

    private func localName(_ name: String) -> String {
        if let range = name.range(of: ":") {
            return String(name[range.upperBound...])
        }
        return name
    }
}
