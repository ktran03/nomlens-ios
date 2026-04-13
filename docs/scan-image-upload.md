# Scan Image Upload — Module Overview

## What it does

When a user contributes a decoded scan to the public archive, the source photo is uploaded to Supabase Storage under a deterministic path keyed to the source and scan UUIDs. The upload is **best-effort**: if it fails, the contribution (source record, scan record, characters) still commits successfully.

---

## Full contribution pipeline

`ContributionSheet.submit()` runs five sequential async steps:

| Step | API call | Endpoint | Result used by |
|------|----------|----------|----------------|
| 1 | `createSource` | `POST /rest/v1/sources` | Provides `source.id` for all later steps |
| 2 | *(local)* | — | Maps `CharacterDecodeResult` → `NLScan.DecodeResult` array |
| 3 | `createScan` | `POST /rest/v1/scans` | Provides `scan.id` for image path |
| 4 | `uploadScanImage` | `POST /storage/v1/object/scan-images/…` | Best-effort; failure is swallowed with `try?` |
| 5 | `insertCharacters` | `POST /rest/v1/characters` | Bulk insert; throws on failure |

---

## Image upload detail (`SupabaseClient.uploadScanImage`)

### JPEG encoding

```swift
// ContributionSheet — calls before uploadScanImage:
if let jpeg = ImageUtilities.jpegData(from: sourceImage) { … }

// ImageUtilities.jpegData:
static func jpegData(from image: UIImage, quality: CGFloat = 0.9) -> Data? {
    image.jpegData(compressionQuality: quality)
}
```

`jpegData` is the simple path: UIKit's `jpegData(compressionQuality:)` at 90% quality. Compare with `base64JPEG` (used by the Claude API path), which has three fallbacks for thread-safety and non-standard color spaces. The upload path only calls `jpegData`, so it only works reliably when called on or after the main thread — which is fine here since the Task is spawned from `@MainActor`-isolated SwiftUI code.

### Storage path convention

```
scan-images/{sourceId-lowercase}/{scanId-lowercase}/original.jpg
```

Example:
```
scan-images/a3b2c1d0-…/f9e8d7c6-…/original.jpg
```

Both UUIDs are lowercased via `.uuidString.lowercased()`.

### Request construction

```swift
func uploadScanImage(_ data: Data, sourceId: UUID, scanId: UUID) async throws -> String {
    let base = try requiredBase()  // https://nqdxtcsclxzbuqwzqxdz.supabase.co
    let imagePath = "\(sourceId.uuidString.lowercased())/\(scanId.uuidString.lowercased())/original.jpg"
    let uploadURL = base.appendingPathComponent("storage/v1/object/scan-images/\(imagePath)")

    var req = request(url: uploadURL, method: "POST")
    req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
    req.httpBody = data
    let (_, response) = try await session.data(for: req)
    try validate(response: response)

    return base.appendingPathComponent("storage/v1/object/public/scan-images/\(imagePath)").absoluteString
}
```

Headers applied by `request(url:method:)`:
- `apikey: <anonKey>`
- `Authorization: Bearer <anonKey>`
- `Content-Type: image/jpeg` (added in uploadScanImage)

### Return value — public CDN URL

The method returns the public URL:
```
https://nqdxtcsclxzbuqwzqxdz.supabase.co/storage/v1/object/public/scan-images/{path}
```

**Current limitation**: this URL is not written back to the `scans` table. `NewScan.imagePath` is hardcoded `nil` when creating the scan record (step 3 runs before step 4). The scan row exists in Postgres with `image_path = NULL` even after a successful upload.

---

## Data flow diagram

```
UIImage (sourceImage)
    │
    ▼
ImageUtilities.jpegData(from:)          → Data (JPEG, 90% quality)
    │
    ▼
SupabaseClient.uploadScanImage(
    data,
    sourceId: source.id,                ← from step 1
    scanId: scan.id                     ← from step 3
)
    │
    ├── URL: POST /storage/v1/object/scan-images/{sourceId}/{scanId}/original.jpg
    ├── Headers: apikey, Authorization, Content-Type: image/jpeg
    ├── Body: raw JPEG bytes
    │
    ▼
Supabase Storage bucket: scan-images
    │
    ▼
Public CDN URL returned (discarded — not persisted back to scan row)
```

---

## Known issues / gaps

### 1. `imagePath` never written to the scan row

The scan is created (step 3) with `imagePath: nil`, then the image is uploaded (step 4), but the returned URL is never PATCHed back to the `scans` table. Fixing this requires either:
- **Option A**: Upload the image first (before creating the scan), compute the path locally, then include it in `NewScan`. Risk: orphaned storage object if scan creation fails.
- **Option B**: After upload, PATCH `/rest/v1/scans?id=eq.{scanId}` with `{ "image_path": "<url>" }`. Clean but requires an extra round trip and a new `SupabaseClient.updateScan` method.

### 2. `UIKit` imported in `SupabaseClient` for `deviceId`

```swift
import UIKit  // line 2 — causes "No such module 'UIKit'" in test targets

nonisolated static var deviceId: String {
    UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
}
```

The test targets don't link UIKit, so Xcode surfaces a diagnostic. Fix: move `deviceId` to a separate `DeviceIdentifier.swift` file inside a `#if canImport(UIKit)` guard, or use `Foundation`'s `ProcessInfo` as a fallback in tests.

### 3. Upload is fire-and-forget with no retry

`try?` discards both the URL and any error. A network blip silently leaves the scan without an image. Consider logging the failure at minimum:

```swift
do {
    _ = try await client.uploadScanImage(jpeg, sourceId: source.id, scanId: scan.id)
} catch {
    print("[NomLens·SB] image upload failed (non-fatal): \(error)")
}
```

---

## Files involved

| File | Role |
|------|------|
| `Views/ContributionSheet.swift` | Orchestrates the 5-step pipeline; calls `uploadScanImage` |
| `Services/SupabaseClient.swift` | `uploadScanImage(_:sourceId:scanId:)` — HTTP POST to Storage |
| `Utilities/ImageUtilities.swift` | `jpegData(from:)` — encodes UIImage to JPEG Data |
| `Models/ArchiveModels.swift` | `NewScan` (has `imagePath: String?` field, currently always nil) |
| `Services/SupabaseConfig.swift` | Base URL and anon key used by the Storage request |
