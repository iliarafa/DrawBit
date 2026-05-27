import SwiftUI
import UIKit

struct ShareSheet: View {
    let piece: Piece
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedScale: Int
    @State private var selectedFormat: ExportFormat
    @State private var isExporting = false

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
            case .apng:        "MP4"
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
    }

    init(piece: Piece) {
        self.piece = piece
        self._selectedScale = State(initialValue: Self.defaultScale(for: piece.size))
        // PNG default — animated formats are opt-in.
        self._selectedFormat = State(initialValue: .png)
    }

    private let scales = [1, 2, 4, 8, 16]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.10).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Spacer(minLength: 0)

                    Text("FORMAT")
                        .font(.pixel(11))
                        .foregroundStyle(.white.opacity(0.55))

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: 8
                    ) {
                        ForEach(ExportFormat.allCases) { f in
                            formatTile(format: f)
                        }
                    }

                    Text("SCALE")
                        .font(.pixel(11))
                        .foregroundStyle(.white.opacity(0.55))

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                        spacing: 8
                    ) {
                        ForEach(scales, id: \.self) { s in
                            scaleTile(scale: s)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EXPORT")
                        .font(.pixel(14))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("CANCEL")
                            .font(.pixel(12))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await share() }
                    } label: {
                        if isExporting {
                            ProgressView().tint(.white)
                        } else {
                            Text("EXPORT")
                                .font(.pixel(12))
                                .foregroundStyle(.white)
                        }
                    }
                    .disabled(isExporting)
                    .accessibilityIdentifier("ShareSheet.export")
                }
            }
            .toolbarBackground(Color(white: 0.10), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(edge)×\(edge)")
                        .font(.pixel(8))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ShareSheet.scale.\(s)")
    }

    private static func defaultScale(for size: CanvasSize) -> Int {
        switch size {
        case .s16: 16
        case .s32: 16
        case .s64: 8
        case .s128: 4
        }
    }

    private func share() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        let size = piece.size
        let scale = selectedScale
        let format = selectedFormat

        // Load whatever the format needs from the piece. Animated formats walk the
        // full sequence; PNG only needs the active frame.
        let repo = PieceRepository(context: modelContext)
        let activeFrame: Frame
        let allFrames: [Frame]
        let fps: Int
        do {
            let loaded = try repo.loadFrames(piece: piece)
            activeFrame = loaded.frames[loaded.activeFrameIndex]
            allFrames = loaded.frames
            fps = loaded.fps
        } catch {
            return
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
                data = try? GIFExporter.export(frames: allFrames, size: size, scale: scale, fps: fps)
            case .apng:
                data = try? APNGExporter.export(frames: allFrames, size: size, scale: scale, fps: fps)
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
