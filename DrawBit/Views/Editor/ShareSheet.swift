import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareSheet: View {
    let piece: Piece
    /// Frame count from the live editor state. Passed in (rather than re-decoded
    /// from `piece.frameData`) so the budget predicate has the right input
    /// immediately — the share sheet has no `.task` of its own.
    let frameCount: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedScale: Int
    @State private var selectedFormat: ExportFormat
    @State private var isExporting = false
    /// Transient — flips the Copy PNG label to "COPIED" for a moment after a successful copy.
    @State private var didCopy = false

    // Preloaded once for the live preview; reused by `share()` so the piece isn't decoded twice.
    @State private var frames: [Frame] = []
    @State private var activeIndex = 0
    @State private var fps = 12

    /// Sampled, decompressed time-lapse keyframes (RGBA canvases), ready for the
    /// FILM preview + MP4 export. Empty ⇒ nothing recorded yet (tile disabled).
    @State private var filmRGBA: [Data] = []

    /// Below this, the FILM tile is disabled (no motion to show).
    private static let minFilmFrames = 2

    private var outputWidth: Int { piece.size.width * selectedScale }
    private var outputHeight: Int { piece.size.height * selectedScale }

    /// Film keyframes wrapped as single-layer Frames so ExportPreview renders them
    /// through the existing pipeline.
    private var filmFrames: [Frame] {
        filmRGBA.map { rgba in
            let l = Layer(name: "", pixels: rgba)
            return Frame(layers: [l], activeLayerID: l.id)
        }
    }

    private var previewFrames: [Frame] { selectedFormat == .film ? filmFrames : frames }
    private var previewFPS: Int { selectedFormat == .film ? Timelapse.clipFPS : fps }

    /// Output formats. PNG always works (single-frame snapshot of the active frame);
    /// GIF and APNG are animated and require the underlying piece to actually have
    /// multiple frames to be interesting, but exporting a single-frame piece as
    /// either is still valid (you get a one-frame animation that loops on itself).
    enum ExportFormat: String, CaseIterable, Identifiable {
        case png
        case gif
        case apng
        case spriteSheet
        /// The time-lapse: an MP4 of the drawing's recorded process (not the current
        /// frames). Different SOURCE from the others, but users read it as "the film
        /// of it" so it lives in the same FORMAT grid.
        case film
        var id: String { rawValue }

        var label: String {
            switch self {
            case .png:         "PNG"
            case .gif:         "GIF"
            case .apng:        "APNG"
            case .spriteSheet: "Sprite"
            case .film:        "FILM"
            }
        }

        var fileExtension: String {
            switch self {
            case .png:         "png"
            case .gif:         "gif"
            case .apng:        "apng"
            case .spriteSheet: "png"
            case .film:        "mp4"
            }
        }

        /// Maps to the Foundation-only enum the budget predicate uses.
        var budgetKind: ExportSizeBudget.Format {
            switch self {
            case .png:         .png
            case .gif:         .gif
            case .apng:        .apng
            case .spriteSheet: .spriteSheet
            case .film:        .film
            }
        }
    }

    init(piece: Piece, frameCount: Int = 1) {
        self.piece = piece
        self.frameCount = max(1, frameCount)
        self._selectedScale = State(initialValue: Self.defaultScale(for: piece.size))
        // PNG default — animated formats are opt-in.
        self._selectedFormat = State(initialValue: .png)
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            ExportPreview(
                frames: previewFrames,
                activeIndex: selectedFormat == .film ? 0 : activeIndex,
                size: piece.size,
                fps: previewFPS,
                format: selectedFormat,
                outputWidth: outputWidth,
                outputHeight: outputHeight
            )

            Text(piece.effectiveName)
                .font(.pixel(11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)

            section(title: "FORMAT", columns: 5) {
                ForEach(ExportFormat.allCases) { formatTile(format: $0) }
            }

            section(title: "SIZE", columns: 5) {
                ForEach(Self.scales(for: piece.size), id: \.self) { scaleTile(scale: $0) }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                exportButton
                copyButton
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.10).ignoresSafeArea())
        .onAppear { loadFramesIfNeeded() }
        .onChange(of: selectedFormat) { _, newFormat in
            // Switching to a format with a tighter budget (e.g. PNG → sprite sheet at high
            // frame counts) can leave `selectedScale` pointing at a now-disabled tile. Snap it
            // down to the largest tile that still fits so EXPORT never targets a doomed config.
            if isOverBudget(scale: selectedScale, format: newFormat),
               let safe = Self.scales(for: piece.size).reversed()
                   .first(where: { !isOverBudget(scale: $0, format: newFormat) })
            {
                selectedScale = safe
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("EXPORT")
                .font(.pixel(14))
                .foregroundStyle(.white)
            HStack {
                Button { dismiss() } label: {
                    Text("CANCEL")
                        .font(.pixel(12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityIdentifier("ShareSheet.cancel")
                Spacer()
            }
        }
    }

    private func section<Content: View>(
        title: String, columns: Int, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.pixel(11))
                .foregroundStyle(.white.opacity(0.55))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
                spacing: 8,
                content: content
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportButton: some View {
        Button {
            Task { await share() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.white)
                if isExporting {
                    ProgressView().tint(.black)
                } else {
                    Text("EXPORT")
                        .font(.pixel(14))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
        .accessibilityIdentifier("ShareSheet.export")
    }

    /// Secondary action: copy the active frame as a PNG straight to the clipboard, so a still can
    /// be pasted into another app without the system share sheet. Copies at the selected SIZE.
    private var copyButton: some View {
        Button { copyPNG() } label: {
            Text(didCopy ? "COPIED" : "COPY PNG")
                .font(.pixel(11))
                .foregroundStyle(.white.opacity(didCopy ? 0.9 : 0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ShareSheet.copyPNG")
    }

    private func copyPNG() {
        let size = piece.size
        let scale = selectedScale
        let frame: Frame
        if !frames.isEmpty {
            frame = frames[activeIndex]
        } else if let loaded = try? PieceRepository(context: modelContext).loadFrames(piece: piece) {
            frame = loaded.frames[loaded.activeFrameIndex]
        } else {
            return
        }
        guard let data = PNGExporter.export(frame: frame, size: size, scale: scale) else { return }
        UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }

    private func loadFramesIfNeeded() {
        guard frames.isEmpty else { return }
        let repo = PieceRepository(context: modelContext)
        if let loaded = try? repo.loadFrames(piece: piece) {
            frames = loaded.frames
            activeIndex = loaded.activeFrameIndex
            fps = loaded.fps
        }
        // Decode + evenly sample + decompress the recorded process for the FILM tile.
        let compressed = piece.timelapseData.flatMap { TimelapseCodec.decode($0) } ?? []
        filmRGBA = Timelapse.sample(compressed, to: Timelapse.targetClipFrames)
            .compactMap { KeyframeCodec.decompress($0) }
    }

    private func formatTile(format f: ExportFormat) -> some View {
        let isSelected = f == selectedFormat
        // FILM needs at least a couple of recorded steps to be worth exporting.
        let disabled = f == .film && filmRGBA.count < Self.minFilmFrames
        return Button {
            selectedFormat = f
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.04))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.15),
                            lineWidth: isSelected ? 2 : 0.5)
                VStack(spacing: 2) {
                    Text(f.label)
                        .font(.pixel(14))
                        .foregroundStyle(.white.opacity(disabled ? 0.3 : 1))
                        .lineLimit(1)
                    if disabled {
                        Text("KEEP DRAWING")
                            .font(.pixel(7))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("ShareSheet.format.\(f.rawValue)")
    }

    private func scaleTile(scale s: Int) -> some View {
        let outW = piece.size.width * s
        let outH = piece.size.height * s
        // Square → one number; non-square → the full W×H (one number can't describe it).
        let label = outW == outH ? "\(outW)" : "\(outW)×\(outH)"
        let isSelected = s == selectedScale
        let overBudget = isOverBudget(scale: s, format: selectedFormat)
        // Surface the predicate verdict up front rather than letting the
        // exporter return `nil` and the share popover silently no-op.
        let primaryOpacity = overBudget ? 0.30 : 1.0
        let secondaryOpacity = overBudget ? 0.40 : 0.55
        return Button {
            selectedScale = s
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.04))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.15),
                            lineWidth: isSelected ? 2 : 0.5)
                VStack(spacing: 2) {
                    // The actual exported size in px: one number when square, W×H when not.
                    // "TOO BIG" only appears on over-budget tiles, keeping normal tiles tidy.
                    // `verbatim:` to bypass SwiftUI's LocalizedStringKey number grouping —
                    // we want "1920", not a comma-grouped "1,920".
                    Text(verbatim: label)
                        .font(.pixel(12))
                        .foregroundStyle(.white.opacity(primaryOpacity))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if overBudget {
                        Text("TOO BIG")
                            .font(.pixel(8))
                            .foregroundStyle(.white.opacity(secondaryOpacity))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            // Deliberately shorter and quieter than the 56pt FORMAT tiles — SIZE
            // is the secondary choice on this sheet. 44pt is the hit-target floor.
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(overBudget)
        .accessibilityIdentifier("ShareSheet.scale.\(s)")
    }

    /// Wraps `ExportSizeBudget.isOverBudget` with this view's piece + frame
    /// count. Used by `scaleTile` to gray itself out, and by the format-change
    /// hook below to snap `selectedScale` back into the safe range so the
    /// EXPORT button never points at a doomed config.
    private func isOverBudget(scale s: Int, format f: ExportFormat) -> Bool {
        ExportSizeBudget.isOverBudget(
            format: f.budgetKind,
            canvasWidth: piece.size.width,
            canvasHeight: piece.size.height,
            scale: s,
            frameCount: frameCount
        )
    }

    /// Five export scales per canvas — every canvas hits the same output edges
    /// (128 / 256 / 512 / 1024 / 2048 px), with the multiplier sliding to compensate.
    /// Users effectively pick an *output size*; we just spell it as a magnification
    /// number to keep the math integer (each source pixel becomes an exact N×N
    /// block on output — see `PNGExporter.swift:24-25`, nearest-neighbour everywhere).
    static func scales(for size: CanvasSize) -> [Int] {
        // A power-of-two ladder anchored so output edges land near
        // 128/256/512/1024/2048 px. `k` is the smallest multiplier (~128 / dimension),
        // and the five scales are k·{1,2,4,8,16}. Integer floor keeps each source pixel
        // an exact block on output (nearest-neighbour everywhere). This reproduces the
        // old per-preset table exactly (16→[8,16,32,64,128] … 128→[1,2,4,8,16]) and
        // generalises to any custom square (48→[2,4,8,16,32], 8→[16,32,64,128,256]).
        // Anchors to the LONGEST edge so it lands near 128…2048; the short edge scales
        // by the same k. Square is the longestEdge == dimension case (unchanged).
        let k = max(1, 128 / size.longestEdge)
        return [1, 2, 4, 8, 16].map { k * $0 }
    }

    /// Default lands at 1024–2048 px output regardless of canvas. iOS Photos
    /// (and most social platforms) renders images through bilinear smoothing at
    /// non-1:1 zoom — a 256 px export looks soft in the Photos preview even when
    /// the file bytes are mathematically pixel-perfect. 1024 px+ is the community
    /// standard that survives the smoothing; see Pixaki's user-guide note on
    /// nearest-neighbour magnification (every dedicated pixel-art app ships
    /// bigger-by-default for this reason).
    static func defaultScale(for size: CanvasSize) -> Int {
        // Small canvases default to ~1024 px output, larger ones to ~2048 px (bigger
        // sources can afford—and benefit from—the crisper larger export). Pick the
        // scale whose output edge lands closest to that target. Reproduces the old
        // per-preset defaults (16→64, 32→32, 64→32, 128→16) and generalises.
        let d = size.longestEdge
        let target = d <= 32 ? 1024 : 2048
        return scales(for: size).min(by: { abs($0 * d - target) < abs($1 * d - target) }) ?? 1
    }

    private func share() async {
        guard !isExporting else { return }
        // Defense-in-depth: the tile is already disabled when this would fail,
        // and `selectedScale` is snapped to a safe value on format change, but
        // if either of those slips we still bail before the exporter no-ops.
        guard !isOverBudget(scale: selectedScale, format: selectedFormat) else { return }
        isExporting = true
        defer { isExporting = false }

        let size = piece.size
        let scale = selectedScale
        let format = selectedFormat

        // Prefer the frames already loaded for the preview; fall back to a fresh decode if the
        // export somehow fires before `onAppear` populated them. Animated formats walk the full
        // sequence; PNG only needs the active frame.
        let allFrames: [Frame]
        let activeFrame: Frame
        let exportFPS: Int
        if !frames.isEmpty {
            allFrames = frames
            activeFrame = frames[activeIndex]
            exportFPS = fps
        } else {
            let repo = PieceRepository(context: modelContext)
            guard let loaded = try? repo.loadFrames(piece: piece) else { return }
            allFrames = loaded.frames
            activeFrame = loaded.frames[loaded.activeFrameIndex]
            exportFPS = loaded.fps
        }

        let sizeTag = piece.size.isSquare ? "\(piece.size.width)" : "\(piece.size.width)x\(piece.size.height)"
        let filename = "drawbit-\(sizeTag)-\(scale)x.\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        // NOTE: the animated exporters now check `Task.checkCancellation()` between
        // frames, so they'll bail cleanly if this detached task is cancelled. There's
        // currently no UI to cancel a running export — wiring a CANCEL button (or
        // auto-cancel on ShareSheet dismiss) is the follow-up that makes the
        // checkpoints actually fire. Until then, `try?` here swallows the
        // theoretical CancellationError the same way it swallows other failures.
        // Lift the film keyframes into a local so the detached task doesn't capture `self`.
        let film = filmRGBA

        let writtenURL: URL? = await Task.detached(priority: .userInitiated) {
            // Film writes the MP4 straight to `url`; the others produce Data we then write.
            if format == .film {
                do {
                    try MP4Exporter.export(keyframes: film, size: size, scale: scale,
                                           fps: Timelapse.clipFPS, to: url)
                    return url
                } catch {
                    return nil
                }
            }
            let data: Data?
            switch format {
            case .png:
                data = PNGExporter.export(frame: activeFrame, size: size, scale: scale)
            case .gif:
                data = try? GIFExporter.export(frames: allFrames, size: size, scale: scale, fps: exportFPS)
            case .apng:
                data = try? APNGExporter.export(frames: allFrames, size: size, scale: scale, fps: exportFPS)
            case .spriteSheet:
                data = SpriteSheetExporter.export(frames: allFrames, size: size, scale: scale)
            case .film:
                data = nil   // handled above
            }
            guard let data else { return nil }
            do {
                try data.write(to: url)
                return url
            } catch {
                return nil
            }
        }.value

        guard let writtenURL else { return }

        let vc = UIActivityViewController(activityItems: [writtenURL], applicationActivities: nil)
        vc.excludedActivityTypes = [
            UIActivity.ActivityType("com.apple.reminders.RemindersEditorExtension"),
            UIActivity.ActivityType("com.apple.reminders.sharingextension"),
        ]
        guard let presenter = UIApplication.shared.topmostViewController else { return }
        if let popover = vc.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.maxY - 60,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        vc.completionWithItemsHandler = { _, _, _, _ in
            dismiss()
        }
        presenter.present(vc, animated: true)
    }
}

private extension UIApplication {
    var activeWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }

    var topmostViewController: UIViewController? {
        var top = activeWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
