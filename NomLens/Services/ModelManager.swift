import Foundation
import CryptoKit
import CoreML
import ZIPFoundation

// MARK: - Manifest

/// JSON served by the model version endpoint.
///
/// Example:
/// ```json
/// { "version": "1.0.0", "url": "https://…/nom_classifier_1.0.0.mlpackage.zip", "sha256": "abc123…" }
/// ```
struct ModelManifest: Codable {
    let version: String
    let url: URL
    let sha256: String
}

// MARK: - Errors

enum ModelManagerError: Error {
    /// Downloaded file SHA-256 does not match the manifest. File is discarded.
    case hashMismatch(expected: String, actual: String)
    /// Server returned a non-200 status.
    case httpError(Int)
    /// Model file exists on disk but Core ML refused to load it.
    case loadFailed(Error)
    /// No .mlpackage found inside the downloaded zip.
    case mlpackageNotFoundInZip
}

// MARK: - ModelManager

/// Downloads, verifies, and hot-swaps the on-device Han Nôm classifier.
///
/// **Lifecycle (call from `ServiceContainer` on startup):**
/// ```swift
/// Task { await modelManager.loadStoredModel() }   // restore last-known-good immediately
/// Task { await modelManager.checkForUpdates() }   // silently fetch newer version in background
/// ```
///
/// The manager writes models to `Application Support/NomLens/models/` and tracks
/// the current version in `UserDefaults`. On hash failure the download is deleted
/// and the previous model remains active.
actor ModelManager {

    // MARK: - Configuration

    /// Override in tests or staging builds.
    static var manifestURL = URL(string: "https://pub-0102465855154079b794681a5533bc05.r2.dev/manifest.json")!

    /// Name and version of the model bundled with the app binary.
    /// Update these when shipping a new bundled model.
    static let bundledModelName    = "NomLensClassifier_3.0.0"
    static let bundledModelVersion = "3.0.0"

    static let versionKey          = "nomModelVersion"
    private static let modelsDirName  = "NomLens/models"

    /// The version of the model currently active on this device.
    /// Returns whichever is higher: the stored (downloaded) version or the bundled version.
    static var activeVersion: String {
        let stored = UserDefaults.standard.string(forKey: versionKey)
        guard let stored else { return bundledModelVersion }
        return isVersion(bundledModelVersion, newerThan: stored) ? bundledModelVersion : stored
    }

    // MARK: - Dependencies

    private let proxy:        ClassifierProxy
    private let httpClient:   HTTPClient
    private let modelsDir:    URL
    /// Called on the main actor once a model is successfully loaded.
    private let onReady:      (@MainActor () -> Void)?

    // MARK: - Init

    init(
        proxy: ClassifierProxy,
        httpClient: HTTPClient = URLSession.shared,
        modelsDirectory: URL? = nil,
        onReady: (@MainActor () -> Void)? = nil
    ) {
        self.proxy      = proxy
        self.httpClient = httpClient
        self.modelsDir  = modelsDirectory ?? Self.defaultModelsDirectory()
        self.onReady    = onReady
    }

    // MARK: - Public API

    /// Loads the previously downloaded model from disk immediately (synchronous
    /// file read — call once at startup before the first decode pass).
    func loadStoredModel() async {
        guard let version = storedVersion,
              let modelURL = candidateURL(for: version),
              FileManager.default.fileExists(atPath: modelURL.path)
        else { return }

        activate(modelURL: modelURL, version: version)
    }

    /// Directly load a model from a local URL — for development/testing only.
    func loadModel(at url: URL) {
        // Extract just the version number from filenames like "NomLensClassifier_3.0.0"
        let stem = url.deletingPathExtension().lastPathComponent
        let version = stem.components(separatedBy: "_").last ?? stem
        activate(modelURL: url, version: version)
    }

    /// Loads the model bundled with the app binary when no downloaded model is
    /// present OR when the bundled version is newer than the stored version.
    /// Safe to call after `loadStoredModel()`.
    func loadBundledModelIfNeeded() async {
        let bundledVersion = ModelManager.bundledModelVersion
        if let stored = storedVersion, !Self.isVersion(bundledVersion, newerThan: stored) {
            return // downloaded model is same age or newer — keep it
        }
        let name = ModelManager.bundledModelName
        // Xcode compiles .mlpackage → .mlmodelc at build time; try compiled first.
        if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            activate(modelURL: url, version: bundledVersion)
        }
    }

    /// Returns true if `a` is a higher semantic version than `b`.
    /// Compares dot-separated integer tuples; non-numeric components sort as 0.
    private static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let parse: (String) -> [Int] = {
            $0.split(separator: ".").map { Int($0) ?? 0 }
        }
        let av = parse(a), bv = parse(b)
        let len = max(av.count, bv.count)
        for i in 0..<len {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }

    /// Hits the manifest endpoint and downloads a newer model if one exists.
    /// Safe to call in a background `Task` — never throws to the caller.
    func checkForUpdates() async {
        do {
            let manifest = try await fetchManifest()

            guard manifest.version != storedVersion else { return }

            try await download(manifest: manifest)
        } catch {
            // Update failures are non-fatal — current model stays active.
            print("[NomLens] ModelManager update failed: \(error)")
        }
    }

    // MARK: - Internal (internal for tests)

    /// Verifies `fileURL` against `expectedHex`. Throws `hashMismatch` on failure.
    func verifyHash(fileURL: URL, expectedHex: String) throws {
        let data   = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expectedHex else {
            throw ModelManagerError.hashMismatch(expected: expectedHex, actual: actual)
        }
    }

    // MARK: - Private

    private var storedVersion: String? {
        get { UserDefaults.standard.string(forKey: Self.versionKey) }
    }

    private func setStoredVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: Self.versionKey)
    }

    private func fetchManifest() async throws -> ModelManifest {
        let request = URLRequest(url: ModelManager.manifestURL, timeoutInterval: 10)
        let (data, response) = try await httpClient.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ModelManagerError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(ModelManifest.self, from: data)
    }

    private func download(manifest: ModelManifest) async throws {
        let fm = FileManager.default

        // 1. Download zip to a temp file.
        let tempZip = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        let request = URLRequest(url: manifest.url)
        let (data, response) = try await httpClient.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ModelManagerError.httpError(http.statusCode)
        }
        try data.write(to: tempZip, options: .atomic)

        // 2. Verify SHA-256 of the zip before touching anything.
        do {
            try verifyHash(fileURL: tempZip, expectedHex: manifest.sha256)
        } catch {
            try? fm.removeItem(at: tempZip)
            throw error
        }

        // 3. Extract zip to a temp directory.
        let tempExtract = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempExtract, withIntermediateDirectories: true)
        do {
            try fm.unzipItem(at: tempZip, to: tempExtract)
        } catch {
            try? fm.removeItem(at: tempZip)
            try? fm.removeItem(at: tempExtract)
            throw error
        }
        try? fm.removeItem(at: tempZip)

        // 4. Find the .mlpackage inside the extracted content.
        let contents = (try? fm.contentsOfDirectory(at: tempExtract,
                                                     includingPropertiesForKeys: nil)) ?? []
        guard let packageURL = contents.first(where: { $0.pathExtension == "mlpackage" }) else {
            try? fm.removeItem(at: tempExtract)
            throw ModelManagerError.mlpackageNotFoundInZip
        }

        // 5. Move verified package into the models directory.
        try fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let destURL = modelsDir.appendingPathComponent("\(manifest.version).mlpackage")
        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
        try fm.moveItem(at: packageURL, to: destURL)
        try? fm.removeItem(at: tempExtract)

        // 6. Activate; version persisted only after successful load.
        activate(modelURL: destURL, version: manifest.version)
    }

    private func activate(modelURL: URL, version: String) {
        do {
            // Use a cached .mlmodelc if available — avoids recompiling on every launch.
            let loadURL = compiledURL(for: version) ?? modelURL
            let classifier = try NomClassifier(modelURL: loadURL)

            // If we compiled from a .mlpackage, cache the result for next launch.
            if loadURL == modelURL, modelURL.pathExtension != "mlmodelc" {
                cacheCompiledModel(from: modelURL, version: version)
            }

            Task { await proxy.update(classifier) }
            setStoredVersion(version)
            print("[NomLens] ModelManager loaded model v\(version)")
            if let onReady {
                Task { @MainActor in onReady() }
            }
        } catch {
            print("[NomLens] ModelManager failed to load model v\(version): \(error)")
        }
    }

    private func compiledURL(for version: String) -> URL? {
        let url = modelsDir.appendingPathComponent("\(version).mlmodelc")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func cacheCompiledModel(from packageURL: URL, version: String) {
        do {
            let temp = try MLModel.compileModel(at: packageURL)
            let dest = modelsDir.appendingPathComponent("\(version).mlmodelc")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: temp, to: dest)
            print("[NomLens] ModelManager cached compiled model v\(version)")
        } catch {
            print("[NomLens] ModelManager compile cache failed (non-fatal): \(error)")
        }
    }

    private func candidateURL(for version: String) -> URL? {
        modelsDir.appendingPathComponent("\(version).mlpackage")
    }

    private static func defaultModelsDirectory() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(modelsDirName)
    }
}
