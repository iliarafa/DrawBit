import SwiftUI
import UIKit

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

    // Preloaded once for the live preview; reused by `share()` so the piece isn't decoded twice.
    @State private var frames: [Frame] = []
    @State private var activeIndex = 0
    @State private var fps = 12

    private var outputEdge: Int { piece.size.dimension * selectedScale }

    /// Output formats. PNG always works (single-frame snapshot of the active frame);
    /// GIF and APNG are animated and require the underlying piece to actually have
    /// multiple frames to be interesting, but exporting a single-frame piece as
    /// either is still valid (you get a one-frame animation that loops on itself).
    enum ExportFormat: String, CaseIterable, Identifiable {
        case png
        case gif
        case apng
        case spriteSheet
        var id: String { rawValue }

        var label: String {
            switch self {
            case .png:         "PNG"
            case .gif:         "GIF"
            case .apng:        "APNG"
            case .spriteSheet: "Sprite"
            }
        }

        var fileExtension: String {
            switch self {
            case .png:         "png"
            case .gif:         "gif"
            case .apng:        "apng"
            case .spriteSheet: "png"
            }
        }

        /// Maps to the Foundation-only enum the budget predicate uses.
        var budgetKind: ExportSizeBudget.Format {
            switch self {
            case .png:         .png
            case .gif:         .gif
            case .apng:        .apng
            case .spriteSheet: .spriteSheet
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
                frames: frames,
                activeIndex: activeIndex,
                size: piece.size,
                fps: fps,
                format: selectedFormat,
                outputEdge: outputEdge
            )

            Text(piece.effectiveName)
                .font(.pixel(11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)

            section(title: "FORMAT", columns: 4) {
                ForEach(ExportFormat.allCases) { formatTile(format: $0) }
            }

            section(title: "SCALE", columns: 5) {
                ForEach(Self.scales(for: piece.size), id: \.self) { scaleTile(scale: $0) }
            }

            Spacer(minLength: 0)

            exportButton
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

    private func loadFramesIfNeeded() {
        guard frames.isEmpty else { return }
        let repo = PieceRepository(context: modelContext)
        if let loaded = try? repo.loadFrames(piece: piece) {
            frames = loaded.frames
            activeIndex = loaded.activeFrameIndex
            fps = loaded.fps
        }
    }

    private func formatTile(format f: ExportFormat) -> some View {
        let isSelected = f == selectedFormat
        return Button {
            selectedFormat = f
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.04))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.15),
                            lineWidth: isSelected ? 2 : 0.5)
                Text(f.label)
                    .font(.pixel(14))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ShareSheet.format.\(f.rawValue)")
    }

    private func scaleTile(scale s: Int) -> some View {
        let edge = piece.size.dimension * s
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
                VStack(spacing: 4) {
                    Text("\(s)×")
                        .font(.pixel(14))
                        .foregroundStyle(.white.opacity(primaryOpacity))
                        .lineLimit(1)
                    Text(overBudget ? "TOO BIG" : "\(edge)×\(edge)")
                        .font(.pixel(8))
                        .foregroundStyle(.white.opacity(secondaryOpacity))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
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
            canvasEdge: piece.size.dimension,
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
        // Odd sizes mirror their even neighbour's multipliers — output edges
        // land within a few % of 128/256/512/1024/2048 (15×64 = 960,
        // 31×32 = 992, 63×32 = 2016) which is well inside the platform-resize
        // tolerance that motivated the 1024-px+ default in the first place.
        switch size {
        case .s15, .s16:  [8, 16, 32, 64, 128]   // 128, 256, 512, 1024, 2048
        case .s31, .s32:  [4, 8, 16, 32, 64]     // 128, 256, 512, 1024, 2048
        case .s63, .s64:  [2, 4, 8, 16, 32]      // 128, 256, 512, 1024, 2048
        case .s128:       [1, 2, 4, 8, 16]       // 128, 256, 512, 1024, 2048
        }
    }

    /// Default lands at 1024–2048 px output regardless of canvas. iOS Photos
    /// (and most social platforms) renders images through bilinear smoothing at
    /// non-1:1 zoom — a 256 px export looks soft in the Photos preview even when
    /// the file bytes are mathematically pixel-perfect. 1024 px+ is the community
    /// standard that survives the smoothing; see Pixaki's user-guide note on
    /// nearest-neighbour magnification (every dedicated pixel-art app ships
    /// bigger-by-default for this reason).
    static func defaultScale(for size: CanvasSize) -> Int {
        switch size {
        case .s15, .s16:  64   // 960 / 1024 px
        case .s31, .s32:  32   //  992 / 1024 px
        case .s63, .s64:  32   // 2016 / 2048 px
        case .s128:       16   // 2048 px
        }
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

        let safeName = piece.effectiveName.replacingOccurrences(of: "/", with: "-")
        let filename = "\(safeName)-\(scale)x.\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        // NOTE: the animated exporters now check `Task.checkCancellation()` between
        // frames, so they'll bail cleanly if this detached task is cancelled. There's
        // currently no UI to cancel a running export — wiring a CANCEL button (or
        // auto-cancel on ShareSheet dismiss) is the follow-up that makes the
        // checkpoints actually fire. Until then, `try?` here swallows the
        // theoretical CancellationError the same way it swallows other failures.
        let writtenURL: URL? = await Task.detached(priority: .userInitiated) {
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
