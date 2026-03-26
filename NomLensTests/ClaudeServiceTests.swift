import Testing
import Foundation
import UIKit
@testable import NomLens

// MARK: - Mock HTTP client

/// Captures call timestamps so rate-limit timing can be verified.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {

    struct Call {
        let request: URLRequest
        let timestamp: Date
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.withLock { _calls } }

    /// Responses to return in order. If exhausted, the last one is repeated.
    var responses: [(Data, Int)]  // (body, statusCode)

    init(responses: [(Data, Int)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let call = Call(request: request, timestamp: Date())
        lock.withLock { _calls.append(call) }

        let index = min(_calls.count - 1, responses.count - 1)
        let (body, statusCode) = responses[index]

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}

/// Returns a network timeout error on first call, then succeeds.
final class TimeoutThenSucceedClient: HTTPClient, @unchecked Sendable {

    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int { lock.withLock { _callCount } }

    let successData: Data

    init(successData: Data) {
        self.successData = successData
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let count = lock.withLock { () -> Int in
            _callCount += 1
            return _callCount
        }
        if count == 1 {
            throw URLError(.timedOut)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (successData, response)
    }
}

// MARK: - Helpers

private func makeService(responses: [(Data, Int)]) -> ClaudeService {
    ClaudeService(
        httpClient: MockHTTPClient(responses: responses),
        apiKey: "test-key",
        systemPrompt: "test prompt"
    )
}

private func claudeResponseData(for json: String) -> Data {
    let envelope = """
    {
      "content": [
        { "type": "text", "text": \(JSON.quote(json)) }
      ]
    }
    """
    return envelope.data(using: .utf8)!
}

/// Minimal valid character result JSON.
private let validCharacterJSON = """
{
  "character": "南",
  "type": "han",
  "quoc_ngu": "nam",
  "meaning": "south",
  "confidence": "high",
  "alternate_readings": [],
  "damage_noted": false,
  "notes": null
}
"""

private func makeCrop() -> CharacterCrop {
    // 1×1 white pixel image — sufficient for encode/decode pipeline tests
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
    let image = renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return CharacterCrop(
        id: UUID(),
        image: image,
        boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10),
        observationIndex: 0,
        characterIndex: 0,
        normalizedBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.1)
    )
}

// Small helper to properly JSON-escape a string value
private enum JSON {
    static func quote(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

// MARK: - M2: Response parsing

@MainActor
struct ClaudeResponseParsingTests {

    @Test func parsesValidCharacterResponse() throws {
        let data = claudeResponseData(for: validCharacterJSON)
        // Parse the inner JSON directly (same path as ClaudeService.parseResponse)
        let envelope = try JSONDecoder().decode(ClaudeEnvelope.self, from: data)
        let text = try #require(envelope.content.first?.text)
        let result = try JSONDecoder().decode(CharacterDecodeResult.self, from: Data(text.utf8))
        #expect(result.character == "南")
        #expect(result.quocNgu == "nam")
        #expect(result.confidence == .high)
    }

    @Test func parsesNullCharacterResponse() throws {
        let json = """
        {
          "character": null,
          "type": null,
          "quoc_ngu": null,
          "meaning": null,
          "confidence": "none",
          "alternate_readings": [],
          "damage_noted": true,
          "notes": "too damaged"
        }
        """
        let result = try JSONDecoder().decode(CharacterDecodeResult.self, from: Data(json.utf8))
        #expect(result.character == nil)
        #expect(result.confidence == .none)
        #expect(result.damageNoted == true)
    }

    @Test func stripsMarkdownFencesFromResponse() throws {
        let fenced = "```json\n\(validCharacterJSON)\n```"
        let data = claudeResponseData(for: fenced)
        let envelope = try JSONDecoder().decode(ClaudeEnvelope.self, from: data)
        let rawText = try #require(envelope.content.first?.text)
        // Strip fences the same way ClaudeService does
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), let nl = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: nl)...])
        }
        if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try JSONDecoder().decode(CharacterDecodeResult.self, from: Data(text.utf8))
        #expect(result.character == "南")
    }
}

// Minimal decodable matching ClaudeService's internal APIResponse shape
private struct ClaudeEnvelope: Decodable {
    struct Block: Decodable { let type: String; let text: String? }
    let content: [Block]
}

// MARK: - M2: Network and rate limiting

struct ClaudeServiceNetworkTests {

    @Test func decodeSingleCharacterSucceeds() async throws {
        let service = makeService(responses: [(claudeResponseData(for: validCharacterJSON), 200)])
        let result = try await service.decodeCharacter(makeCrop())
        #expect(result.character == "南")
    }

    @Test func throwsAPIErrorOnHTTP401() async throws {
        let service = makeService(responses: [(Data(), 401)])
        await #expect(throws: DecoderError.apiError(statusCode: 401, message: nil)) {
            try await service.decodeCharacter(makeCrop())
        }
    }

    @Test func throwsAPIErrorOnHTTP429() async throws {
        let service = makeService(responses: [(Data(), 429)])
        await #expect(throws: DecoderError.apiError(statusCode: 429, message: nil)) {
            try await service.decodeCharacter(makeCrop())
        }
    }

    @Test func retriesOnceOnNetworkTimeout() async throws {
        let client = TimeoutThenSucceedClient(
            successData: claudeResponseData(for: validCharacterJSON)
        )
        let service = ClaudeService(httpClient: client, apiKey: "key", systemPrompt: "p")
        let result = try await service.decodeCharacter(makeCrop())
        #expect(result.character == "南")
        #expect(client.callCount == 2)
    }

    @Test func throwsAfterExhaustingRetries() async throws {
        // Two timeouts in a row — should give up and throw
        final class AlwaysTimesOut: HTTPClient, @unchecked Sendable {
            func data(for request: URLRequest) async throws -> (Data, URLResponse) {
                throw URLError(.timedOut)
            }
        }
        let service = ClaudeService(httpClient: AlwaysTimesOut(), apiKey: "key", systemPrompt: "p")
        await #expect(throws: DecoderError.networkTimeout) {
            try await service.decodeCharacter(makeCrop())
        }
    }

    @Test func decodeAllReportsProgressInOrder() async throws {
        let crops = (0..<3).map { _ in makeCrop() }
        let responseData = claudeResponseData(for: validCharacterJSON)
        let service = makeService(responses: Array(repeating: (responseData, 200), count: 3))

        var progressLog: [(Int, Int)] = []
        _ = try await service.decodeAll(crops) { done, total in
            progressLog.append((done, total))
        }

        #expect(progressLog.count == 3)
        #expect(progressLog[0] == (1, 3))
        #expect(progressLog[1] == (2, 3))
        #expect(progressLog[2] == (3, 3))
    }

    @Test func decodeAllRespects200msDelay() async throws {
        let crops = (0..<3).map { _ in makeCrop() }
        let responseData = claudeResponseData(for: validCharacterJSON)
        let client = MockHTTPClient(responses: Array(repeating: (responseData, 200), count: 3))
        let service = ClaudeService(httpClient: client, apiKey: "key", systemPrompt: "p")

        _ = try await service.decodeAll(crops) { _, _ in }

        let calls = client.calls
        #expect(calls.count == 3)

        // Gap between call 0→1 and 1→2 must each be ≥ 190ms (allow 10ms jitter)
        let gap1 = calls[1].timestamp.timeIntervalSince(calls[0].timestamp)
        let gap2 = calls[2].timestamp.timeIntervalSince(calls[1].timestamp)
        #expect(gap1 >= 0.190)
        #expect(gap2 >= 0.190)
    }
}
