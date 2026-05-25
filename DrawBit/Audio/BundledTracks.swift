import Foundation

/// Discovers the bundled DrawBit FM station: every `.m4a`/`.mp3` shipped in the
/// app bundle, sorted by filename. Returns `[]` cleanly when none are present, so
/// the app builds and runs before any audio is added. Foundation only.
enum BundledTracks {
    private static let extensions = ["m4a", "mp3"]

    static func load(bundle: Bundle = .main) -> [AudioTrack] {
        var seen = Set<String>()
        var urls: [URL] = []
        for ext in extensions {
            // xcodegen flattens resources to the bundle root (like the font); also
            // check an "Audio" subdirectory in case folder-reference packaging is
            // used. NB: a missing subdirectory returns an empty array (not nil), so
            // collect from both and dedup rather than `??`-falling-through.
            for subdir in ["Audio", Optional<String>.none] {
                guard let found = bundle.urls(forResourcesWithExtension: ext, subdirectory: subdir) else { continue }
                for url in found where seen.insert(url.path).inserted {
                    urls.append(url)
                }
            }
        }
        return sortedByFileName(urls).map {
            AudioTrack(url: $0, title: prettifyTitle(fileName: $0.lastPathComponent))
        }
    }

    /// Numeric-aware sort by filename so `01-`, `02-`, ..., `10-` order correctly.
    static func sortedByFileName(_ urls: [URL]) -> [URL] {
        urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// "01-chiptune_dawn.m4a" -> "CHIPTUNE DAWN". Drops the extension and an
    /// optional leading track-number prefix, turns `-`/`_` into spaces, uppercases.
    static func prettifyTitle(fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        if let r = name.range(of: #"^\d+\s*[-_ ]\s*"#, options: .regularExpression) {
            name.removeSubrange(r)
        }
        name = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let collapsed = name.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return collapsed.uppercased()
    }
}
