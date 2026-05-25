import Foundation

/// One playable track in the DrawBit FM station. Bundled audio only — `url`
/// points at a file inside the app bundle. Pure value type (Foundation only).
struct AudioTrack: Identifiable, Equatable {
    /// Stable identity derived from the file location.
    let id: String
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.id = url.path
        self.url = url
        self.title = title
    }
}
