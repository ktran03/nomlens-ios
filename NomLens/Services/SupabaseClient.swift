import Foundation
import UIKit

// MARK: - SupabaseClient

/// Pure URLSession client for the NomLens preservation backend.
///
/// URL and anon key are read from `Info.plist` (injected via `Config.xcconfig`).
/// Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in your xcconfig to activate.
actor SupabaseClient {

    static let shared = SupabaseClient()

    private let _baseURL: URL?
    private let anonKey: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    nonisolated var isConfigured: Bool { _baseURL != nil }

    private init() {
        self._baseURL = URL(string: SupabaseConfig.url)
        self.anonKey  = SupabaseConfig.anonKey
        self.session  = URLSession(configuration: .default)

        let dec = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fmt.date(from: str) { return d }
            fmt.formatOptions = [.withInternetDateTime]
            if let d = fmt.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Cannot decode date: \(str)")
        }
        self.decoder = dec

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    // MARK: - Stable device ID (used as contributor token)

    nonisolated static var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    // MARK: - Sources

    func browseSources(limit: Int = 50, offset: Int = 0) async throws -> [NLSource] {
        let url = try restURL("/rest/v1/sources", query: [
            "select":    "*",
            "is_public": "eq.true",
            "order":     "created_at.desc",
            "limit":     "\(limit)",
            "offset":    "\(offset)",
        ])
        return try await get(url: url)
    }

    func sourceDetail(id: UUID) async throws -> NLSource? {
        let url = try restURL("/rest/v1/sources", query: [
            "select":    "*,scans(id,character_count,transliteration,created_at,source_id,contributor_device_id,has_corrections)",
            "id":        "eq.\(id.uuidString.lowercased())",
            "is_public": "eq.true",
        ])
        let results: [NLSource] = try await get(url: url)
        return results.first
    }

    func sourcesNear(lat: Double, lng:Double, radiusKm: Double = 10) async throws -> [NLSourceNear] {
        let url = try path("rest/v1/rpc/sources_near")
        let body: [String: Double] = ["lat": lat, "lng": lng, "radius_km": radiusKm]
        return try await post(url: url, body: body, prefer: nil)
    }

    @discardableResult
    func createSource(_ source: NewSource) async throws -> NLSource {
        let url = try path("rest/v1/sources")
        let results: [NLSource] = try await post(url: url, body: source,
                                                 prefer: "return=representation")
        guard let created = results.first else { throw NomLensAPIError.emptyResponse }
        return created
    }

    // MARK: - Scans

    @discardableResult
    func createScan(_ scan: NewScan) async throws -> NLScan {
        let url = try path("rest/v1/scans")
        let results: [NLScan] = try await post(url: url, body: scan,
                                               prefer: "return=representation")
        guard let created = results.first else { throw NomLensAPIError.emptyResponse }
        return created
    }

    // MARK: - Characters

    func insertCharacters(_ characters: [NewCharacter]) async throws {
        guard !characters.isEmpty else { return }
        let url = try path("rest/v1/characters")
        let _: [NLCharacter] = try await post(url: url, body: characters,
                                              prefer: "resolution=merge-duplicates")
    }

    // MARK: - Storage

    /// Uploads JPEG to the `scan-images` bucket. Returns the public CDN URL.
    func uploadScanImage(_ data: Data, sourceId: UUID, scanId: UUID) async throws -> String {
        let base = try requiredBase()
        let imagePath = "\(sourceId.uuidString.lowercased())/\(scanId.uuidString.lowercased())/original.jpg"
        let uploadURL = base.appendingPathComponent("storage/v1/object/scan-images/\(imagePath)")

        var req = request(url: uploadURL, method: "POST")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, response) = try await session.data(for: req)
        try validate(response: response)

        return base.appendingPathComponent("storage/v1/object/public/scan-images/\(imagePath)").absoluteString
    }

    // MARK: - Private

    private func requiredBase() throws -> URL {
        guard let url = _baseURL else { throw NomLensAPIError.notConfigured }
        return url
    }

    private func path(_ segment: String) throws -> URL {
        try requiredBase().appendingPathComponent(segment)
    }

    private func restURL(_ path: String, query: [String: String]) throws -> URL {
        var comps = URLComponents(url: try requiredBase().appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw NomLensAPIError.badURL }
        return url
    }

    private func request(url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func get<T: Decodable>(url: URL) async throws -> T {
        let req = request(url: url, method: "GET")
        print("[NomLens·SB] GET \(url.path)")
        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)
        return try decode(T.self, from: data, context: "GET \(url.lastPathComponent)")
    }

    private func post<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body,
        prefer: String?
    ) async throws -> Response {
        var req = request(url: url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = try encoder.encode(body)
        print("[NomLens·SB] POST \(url.path)")
        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 204 || data.isEmpty {
            return try decoder.decode(Response.self, from: "[]".data(using: .utf8)!)
        }
        return try decode(Response.self, from: data, context: "POST \(url.lastPathComponent)")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, context: String) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            print("[NomLens·SB] decode error (\(context)): \(error)")
            print("[NomLens·SB] raw response: \(String(data: data, encoding: .utf8) ?? "<unreadable>")")
            throw error
        }
    }

    private func validate(response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[NomLens·SB] error \(http.statusCode): \(body)")
            throw NomLensAPIError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}

// MARK: - Errors

enum NomLensAPIError: LocalizedError {
    case notConfigured
    case badURL
    case emptyResponse
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:             return "Supabase URL is not configured."
        case .badURL:                    return "Could not construct request URL."
        case .emptyResponse:             return "Server returned an empty response."
        case .httpError(let code, let b): return "HTTP \(code): \(b)"
        }
    }
}
