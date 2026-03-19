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
        var components = URLComponents(string: "\(baseURL)/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName),
            URLQueryItem(name: "album_name", value: albumName),
            URLQueryItem(name: "duration", value: String(duration))
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
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
        var components = URLComponents(string: "\(baseURL)/search")!
        var items = [URLQueryItem(name: "track_name", value: trackName)]
        if let artist = artistName, !artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components.queryItems = items
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw AppError.lyricsSearchFailed("HTTP request failed")
        }
        return (try? decoder.decode([LRCLibTrack].self, from: data)) ?? []
    }
}
