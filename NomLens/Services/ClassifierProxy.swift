import UIKit

/// A mutable wrapper around `OnDeviceClassifying` that allows `ModelManager`
/// to hot-swap the underlying classifier without rebuilding `RoutingDecoder`.
///
/// `RoutingDecoder` holds a reference to this proxy for its lifetime.
/// When a new model is ready, `ModelManager` calls `update(_:)` and all
/// subsequent classifications use the new model automatically.
///
/// Returns `nil` (→ Claude fallback) when no model has been loaded yet.
actor ClassifierProxy: OnDeviceClassifying {

    private var inner: (any OnDeviceClassifying)?

    /// Replace the active classifier. Thread-safe — actor-isolated.
    func update(_ classifier: any OnDeviceClassifying) {
        inner = classifier
    }

    /// Remove the active classifier (e.g. on rollback).
    func clear() {
        inner = nil
    }

    func classify(crop: UIImage) async throws -> OnDeviceClassification? {
        guard let inner else { return nil }
        return try await inner.classify(crop: crop)
    }
}
