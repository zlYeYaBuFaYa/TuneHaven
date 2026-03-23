import Foundation

protocol LRCLibAPIClientProtocol {
    func get(
        trackName: String,
        artistName: String,
        albumName: String,
        duration: Int
    ) async throws -> LRCLibTrack?

    func search(
        trackName: String,
        artistName: String?
    ) async throws -> [LRCLibTrack]
}

final class LRCLibAPIClient: LRCLibAPIClientProtocol {
    static let shared = LRCLibAPIClient()

    private let baseURL = "https://lrclib.net/api"
    private let userAgent = "TuneHaven/1.0 (iOS Music Player)"
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func get(
        trackName: String,
        artistName: String,
        albumName: String,
        duration: Int
    ) async throws -> LRCLibTrack? {
        guard var components = URLComponents(string: "\(baseURL)/get") else {
            throw AppError.lyricsSearchFailed("无效的 API 地址")
        }
        components.queryItems = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName),
            URLQueryItem(name: "album_name", value: albumName),
            URLQueryItem(name: "duration", value: String(duration))
        ]
        guard let url = components.url else {
            throw AppError.lyricsSearchFailed("无法构建请求 URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.lyricsSearchFailed("无效的 HTTP 响应")
        }
        if http.statusCode == 404 { return nil }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.lyricsSearchFailed("HTTP \(http.statusCode)")
        }
        return try decoder.decode(LRCLibTrack.self, from: data)
    }

    func search(
        trackName: String,
        artistName: String?
    ) async throws -> [LRCLibTrack] {
        guard var components = URLComponents(string: "\(baseURL)/search") else {
            throw AppError.lyricsSearchFailed("无效的 API 地址")
        }
        var items = [URLQueryItem(name: "track_name", value: trackName)]
        if let artist = artistName, !artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw AppError.lyricsSearchFailed("无法构建搜索 URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.lyricsSearchFailed("无效的 HTTP 响应")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.lyricsSearchFailed("HTTP \(http.statusCode)")
        }
        do {
            return try decoder.decode([LRCLibTrack].self, from: data)
        } catch {
            throw AppError.lyricsSearchFailed("响应数据解析失败")
        }
    }
}
