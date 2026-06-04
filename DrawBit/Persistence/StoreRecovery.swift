import Foundation

/// Last-resort recovery for an on-disk SwiftData store that cannot be opened or migrated
/// (for example, one written by an incompatible build during development, or a future
/// migration that fails on a real device).
///
/// Rather than letting `ModelContainer(...)` crash the app on launch, the caller catches
/// the failure and asks this helper to move the store files ASIDE to a timestamped
/// quarantine name. The app then starts with a fresh store. Nothing is ever deleted — the
/// quarantined files remain on disk and are recoverable — so this degrades gracefully
/// without silently destroying a user's work.
enum StoreRecovery {
    /// SwiftData/SQLite store sidecar suffixes that must move together with the main file.
    static let sidecarSuffixes = ["", "-shm", "-wal"]

    /// Renames `<store>`, `<store>-shm`, `<store>-wal` to `<store>.quarantine-<ts>…`.
    /// Best-effort and non-throwing: a sidecar that can't be moved is skipped (the
    /// subsequent fresh-container attempt may still succeed). Returns the destination URLs
    /// that were actually moved (empty when there was nothing on disk yet).
    @discardableResult
    static func moveStoreAside(at storeURL: URL, now: Date = Date()) -> [URL] {
        let fm = FileManager.default
        let stamp = Int(now.timeIntervalSince1970)
        var moved: [URL] = []
        for suffix in sidecarSuffixes {
            let src = storeURL.appendingToFileName(suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = storeURL.appendingToFileName(".quarantine-\(stamp)\(suffix)")
            try? fm.removeItem(at: dst)  // defensive: clear a prior same-second quarantine
            do {
                try fm.moveItem(at: src, to: dst)
                moved.append(dst)
            } catch {
                // Best-effort: leave this sidecar in place and continue.
            }
        }
        return moved
    }
}

extension URL {
    /// Appends `suffix` to the file name component (so `foo.store` + `-wal`
    /// → `foo.store-wal`). Returns `self` unchanged for an empty suffix.
    func appendingToFileName(_ suffix: String) -> URL {
        guard !suffix.isEmpty else { return self }
        return deletingLastPathComponent()
            .appendingPathComponent(lastPathComponent + suffix)
    }
}
