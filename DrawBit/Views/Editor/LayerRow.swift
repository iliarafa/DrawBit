import SwiftUI

struct LayerRow: View {
    let layer: Layer
    let size: CanvasSize
    let isActive: Bool
    let onTap: () -> Void
    let onToggleVisible: () -> Void
    let onToggleLocked: () -> Void
    let isPulsing: Bool
    let onRename: (String) -> Void

    @State private var isEditingName = false
    @State private var draftName = ""

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            if isEditingName {
                TextField("", text: $draftName)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
                    .onSubmit {
                        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != layer.name {
                            onRename(String(trimmed.prefix(32)))
                        }
                        isEditingName = false
                    }
            } else {
                Text(layer.name)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
                    .onLongPressGesture {
                        draftName = layer.name
                        isEditingName = true
                    }
            }
            Spacer()
            Button { onToggleVisible() } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(.white.opacity(layer.isVisible ? 0.85 : 0.45))
            }
            .buttonStyle(.plain)
            Button { onToggleLocked() } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(.white.opacity(layer.isLocked ? 0.85 : 0.45))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.blue.opacity(0.30) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.red.opacity(isPulsing ? 0.85 : 0), lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.18), value: isPulsing)
    }

    private var thumbnail: some View {
        Group {
            if let png = LayerThumbnailRenderer.render(layer: layer, size: size, targetEdge: 64),
               let img = UIImage(data: png)?.cgImage {
                Image(decorative: img, scale: 1.0, orientation: .up)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .frame(width: 32, height: 32)
                    .background(checkerboard)
            } else {
                Rectangle().fill(.gray).frame(width: 32, height: 32)
            }
        }
    }

    private var checkerboard: some View {
        Canvas { ctx, sz in
            let s: CGFloat = 4
            for y in stride(from: 0, to: sz.height, by: s) {
                for x in stride(from: 0, to: sz.width, by: s) {
                    let isDark = (Int(x / s) + Int(y / s)) % 2 == 0
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(isDark ? .gray.opacity(0.4) : .gray.opacity(0.2)))
                }
            }
        }
        .frame(width: 32, height: 32)
    }
}
