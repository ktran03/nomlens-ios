import UIKit
import Foundation

// MARK: - HTTPClient protocol

/// Abstraction over URLSession so ClaudeService can be tested with a mock.
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

// MARK: - Errors

enum DecoderError: Error, Equatable {
    /// Could not encode the crop image as JPEG.
    case imageEncodingFailed
    /// System prompt file missing from app bundle.
    case missingSystemPrompt
    /// Network request timed out after all retries.
    case networkTimeout
    /// HTTP error from the Claude API (e.g. 401, 429, 500).
    case apiError(statusCode: Int, message: String?)
    /// Claude responded but the JSON could not be parsed.
    case invalidJSON(String)
    /// The response content array was empty or had no text block.
    case emptyResponse
}

extension DecoderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Failed to encode image as JPEG."
        case .missingSystemPrompt:
            return "System prompt file is missing from the app bundle."
        case .networkTimeout:
            return "Network request timed out. Please check your connection."
        case .apiError(let statusCode, let message):
            if let message { return "API error \(statusCode): \(message)" }
            return "API error (HTTP \(statusCode))."
        case .invalidJSON(let raw):
            return "Could not parse API response: \(raw.prefix(120))"
        case .emptyResponse:
            return "The API returned an empty response."
        }
    }
}

// MARK: - ClaudeService

/// Sends individual character crop images to the Claude vision API and returns
/// structured `CharacterDecodeResult` values.
///
/// Implemented as an `actor` for Swift 6 data-race safety.
actor ClaudeService {

    // MARK: - Configuration

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model    = "claude-sonnet-4-5"
    private static let maxTokens = 300
    /// Delay between sequential calls in `decodeAll` to avoid rate limiting.
    static let rateLimitDelay: UInt64 = 200_000_000 // 200 ms in nanoseconds

    // MARK: - Dependencies

    private let httpClient: HTTPClient
    private let apiKey: String
    private let systemPrompt: String

    // MARK: - Init

    init(httpClient: HTTPClient = URLSession.shared) throws {
        guard let key = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String,
              !key.isEmpty else {
            throw DecoderError.missingSystemPrompt // reuse until we add a dedicated key error
        }

        guard let url = Bundle.main.url(forResource: "SystemPrompt", withExtension: "txt"),
              let prompt = try? String(contentsOf: url, encoding: .utf8) else {
            throw DecoderError.missingSystemPrompt
        }

        self.httpClient   = httpClient
        self.apiKey       = key
        self.systemPrompt = prompt
    }

    /// Internal init for tests — accepts explicit key and prompt, bypasses bundle loading.
    init(httpClient: HTTPClient, apiKey: String, systemPrompt: String) {
        self.httpClient   = httpClient
        self.apiKey       = apiKey
        self.systemPrompt = systemPrompt
    }

    // MARK: - Public API

    /// Decode a single character crop. Retries once on network timeout.
    func decodeCharacter(_ crop: CharacterCrop) async throws -> CharacterDecodeResult {
        try await decodeWithRetry(crop, attemptsRemaining: 2)
    }

    /// Decode all crops sequentially, reporting progress after each one.
    /// Inserts a `rateLimitDelay` pause between calls.
    func decodeAll(
        _ crops: [CharacterCrop],
        progress: @Sendable @escaping (Int, Int) -> Void
    ) async throws -> [CharacterDecodeResult] {
        var results: [CharacterDecodeResult] = []
        for (index, crop) in crops.enumerated() {
            let result = try await decodeCharacter(crop)
            results.append(result)
            progress(index + 1, crops.count)
            if index < crops.count - 1 {
                try await Task.sleep(nanoseconds: ClaudeService.rateLimitDelay)
            }
        }
        return results
    }

    // MARK: - Private

    private func decodeWithRetry(_ crop: CharacterCrop, attemptsRemaining: Int) async throws -> CharacterDecodeResult {
        do {
            return try await performDecode(crop)
        } catch let urlError as URLError where urlError.code == .timedOut {
            if attemptsRemaining > 1 {
                return try await decodeWithRetry(crop, attemptsRemaining: attemptsRemaining - 1)
            }
            throw DecoderError.networkTimeout
        } catch {
            print("[NomLens] ❌ decodeWithRetry caught: \(error) (type: \(type(of: error)))")
            throw error
        }
    }

    private func performDecode(_ crop: CharacterCrop) async throws -> CharacterDecodeResult {
        print("[NomLens] performDecode — crop id:\(crop.id) box:\(crop.boundingBox) imageSize:\(crop.image.size) hasCG:\(crop.image.cgImage != nil)")
        guard let jpeg = ImageUtilities.base64JPEG(from: crop.image) else {
            print("[NomLens] ❌ base64JPEG returned nil for crop \(crop.id)")
            throw DecoderError.imageEncodingFailed
        }
        print("[NomLens] ✅ base64JPEG OK — length: \(jpeg.count)")

        let request = try buildRequest(base64JPEG: jpeg)
        let (data, response) = try await httpClient.data(for: request)

        if let http = response as? HTTPURLResponse {
            print("[NomLens] HTTP status: \(http.statusCode)")
            if !(200..<300).contains(http.statusCode) {
                let message = Self.extractErrorMessage(from: data)
                if let body = String(data: data, encoding: .utf8) {
                    print("[NomLens] ❌ API error body: \(body.prefix(500))")
                }
                throw DecoderError.apiError(statusCode: http.statusCode, message: message)
            }
        }

        return try parseResponse(data)
    }

    private func buildRequest(base64JPEG: String) throws -> URLRequest {
        var request = URLRequest(url: ClaudeService.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json",      forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,                  forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",            forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model":      ClaudeService.model,
            "max_tokens": ClaudeService.maxTokens,
            "system":     systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type":       "base64",
                                "media_type": "image/jpeg",
                                "data":       base64JPEG
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "Identify this single Han Nôm character."
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(_ data: Data) throws -> CharacterDecodeResult {
        struct APIResponse: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
        }

        let api = try JSONDecoder().decode(APIResponse.self, from: data)

        guard let text = api.content.first(where: { $0.type == "text" })?.text else {
            throw DecoderError.emptyResponse
        }

        let stripped = stripMarkdownFences(text)

        guard let jsonData = stripped.data(using: .utf8) else {
            throw DecoderError.invalidJSON(stripped)
        }

        do {
            return try JSONDecoder().decode(CharacterDecodeResult.self, from: jsonData)
        } catch {
            throw DecoderError.invalidJSON(stripped)
        }
    }

    /// Extracts the human-readable message from a Claude API error response.
    private static func extractErrorMessage(from data: Data) -> String? {
        struct APIError: Decodable {
            struct Inner: Decodable { let message: String }
            let error: Inner?
        }
        return try? JSONDecoder().decode(APIError.self, from: data).error?.message
    }

    /// Strips leading/trailing markdown code fences Claude sometimes adds,
    /// e.g. ```json { ... } ```
    private func stripMarkdownFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            // Remove opening fence and optional language tag (e.g. ```json)
            if let newline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: newline)...])
            }
        }
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
