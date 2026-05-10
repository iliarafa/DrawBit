import SwiftUI

struct FrameRow: View {
    let frame: Frame
    let size: CanvasSize
    let isActive: Bool
    let isEditing: Bool
    let onTap: () -> Void
    let onLongPressRename: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 36, height: 36)
                if let cg = FrameThumbnailRenderer.renderCGImage(frame: frame, size: size, targetEdge: 36) {
                    Image(uiImage: UIImage(cgImage: cg))
                        .interpolation(.none)
                        .antialiased(false)
                        .resizable()
                        .frame(width: 36, height: 36)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isActive ? Color.accentColor : Color.white.opacity(0.15),
                            lineWidth: isActive ? 2 : 1)
            )

            Text(frame.name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.accentColor : Color.white.opacity(0.6))
                .frame(maxWidth: 44)
        }
        .accessibilityIdentifier("FrameRow.\(frame.id.uuidString)")
        .accessibilityAddTraits(.isButton)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onTap() } }
        .onLongPressGesture(minimumDuration: 0.4) { if !isEditing { onLongPressRename() } }
    }
}
