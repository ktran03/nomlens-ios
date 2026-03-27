import Testing
import UIKit
import Foundation
@testable import NomLens

// MARK: - Stubs

private struct StubHTTPClient: HTTPClient {
    let data: Data
    let statusCode: Int

    init(_ encodable: some Encodable, status: Int = 200) throws {
        self.data       = try JSONEncoder().encode(encodable)
        self.statusCode = status
    }

    init(data: Data, status: Int = 200) {
        self.data       = data
        self.statusCode = status
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode,
            httpVersion: nil, headerFields: nil
        )!
        return (data, response)
    }
}

private struct FailingHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

// MARK: - Helpers

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
}

private func makeManager(
    httpClient: HTTPClient = FailingHTTPClient(),
    modelsDir: URL? = nil
) -> (ModelManager, ClassifierProxy) {
    let proxy   = ClassifierProxy()
    let manager = ModelManager(
        proxy: proxy,
        httpClient: httpClient,
        modelsDirectory: modelsDir ?? tempDir()
    )
    return (manager, proxy)
}

// MARK: - Tests

@Suite("ClassifierProxy")
struct ClassifierProxyTests {

    @Test("returns nil when no model loaded")
    func nilWhenEmpty() async throws {
        let proxy = ClassifierProxy()
        let result = try await proxy.classify(crop: UIImage())
        #expect(result == nil)
    }

    @Test("forwards to inner classifier after update")
    func forwardsAfterUpdate() async throws {
        let proxy = ClassifierProxy()
        let stub  = StubOnDeviceClassifier(
            returning: OnDeviceClassification(character: "人", confidence: 0.95)
        )
        await proxy.update(stub)
        let result = try await proxy.classify(crop: UIImage())
        #expect(result?.character == "人")
        #expect(result?.confidence == 0.95)
    }

    @Test("returns nil after clear")
    func nilAfterClear() async throws {
        let proxy = ClassifierProxy()
        let stub  = StubOnDeviceClassifier(
            returning: OnDeviceClassification(character: "人", confidence: 0.95)
        )
        await proxy.update(stub)
        await proxy.clear()
        let result = try await proxy.classify(crop: UIImage())
        #expect(result == nil)
    }
}

@Suite("ModelManager — hash verification")
struct ModelManagerHashTests {

    @Test("accepts file with correct SHA-256")
    func acceptsCorrectHash() async throws {
        let (manager, _) = makeManager()
        let data = Data("hello".utf8)

        // Write to a temp file
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // SHA-256("hello") = 2cf24dba…
        let expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        try await manager.verifyHash(fileURL: url, expectedHex: expected)
        // No throw = pass
    }

    @Test("throws hashMismatch for wrong hash")
    func rejectsWrongHash() async throws {
        let (manager, _) = makeManager()
        let data = Data("hello".utf8)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) {
            try await manager.verifyHash(fileURL: url, expectedHex: "deadbeef")
        }
    }
}

@Suite("ModelManager — update check")
struct ModelManagerUpdateTests {

    @Test("checkForUpdates does nothing when version matches stored")
    func skipsDownloadWhenCurrent() async throws {
        // Seed UserDefaults with a version
        UserDefaults.standard.set("1.0.0", forKey: "nomModelVersion")
        defer { UserDefaults.standard.removeObject(forKey: "nomModelVersion") }

        let manifest = ModelManifest(
            version: "1.0.0",
            url: URL(string: "https://example.com/model.mlpackage")!,
            sha256: "abc"
        )
        let (manager, proxy) = try makeManager(
            httpClient: StubHTTPClient(manifest)
        )
        await manager.checkForUpdates()

        // Proxy should still be empty (no download attempted)
        let result = try await proxy.classify(crop: UIImage())
        #expect(result == nil)
    }

    @Test("checkForUpdates does not crash on network failure")
    func handlesNetworkError() async {
        let (manager, _) = makeManager(httpClient: FailingHTTPClient())
        // Should complete without throwing
        await manager.checkForUpdates()
    }

    @Test("checkForUpdates does not crash on HTTP error")
    func handlesHTTPError() async throws {
        let (manager, _) = try makeManager(
            httpClient: StubHTTPClient(data: Data(), status: 503)
        )
        await manager.checkForUpdates()
    }
}

// MARK: - Stub classifier helper

private struct StubOnDeviceClassifier: OnDeviceClassifying {
    let fixed: OnDeviceClassification?
    init(returning fixed: OnDeviceClassification? = nil) { self.fixed = fixed }
    func classify(crop: UIImage) async throws -> OnDeviceClassification? { fixed }
}
