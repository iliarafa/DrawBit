import SwiftUI

struct FrameRow: View {
    let frame: Frame
    let size: CanvasSize
    let index: Int
    let isActive: Bool
    let frameCount: Int
    let onTap: () -> Void
    let onDuplicate: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    /// Index-based reorder (from, to).
    let onMove: (Int, Int) -> Void

    private static let edge: CGFloat = 46

    /// Show the name overlay only when the user actually named the frame —
    /// suppress the auto-generated "Frame N" names.
    private var showsCustomName: Bool {
        frame.name.range(of: #"^Frame \d+$"#, options: .regularExpression) == nil
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.25))
                .frame(width: Self.edge, height: Self.edge)

            if let cg = FrameThumbnailRenderer.renderCGImage(frame: frame, size: size, targetEdge: Int(Self.edge)) {
                Image(uiImage: UIImage(cgImage: cg))
                    .interpolation(.none)
                    .antialiased(false)
                    .resizable()
                    .frame(width: Self.edge, height: Self.edge)
            }

            // Number badge, top-left.
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("\(index + 1)")
                        .font(.pixel(7))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(isActive ? Color.white : Color.black.opacity(0.7))
                        .foregroundStyle(isActive ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(2)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .frame(width: Self.edge, height: Self.edge)

            // Custom-name overlay, bottom strip.
            if showsCustomName {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(frame.name.uppercased())
                        .font(.pixel(6))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                }
                .frame(width: Self.edge, height: Self.edge)
            }
        }
        .frame(width: Self.edge, height: Self.edge)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isActive ? Color.white : Color.white.opacity(0.15),
                        lineWidth: isActive ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            Button { onDuplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { onRename() } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                .disabled(frameCount <= 1)
        }
        .draggable("\(index)") {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.2))
                .frame(width: Self.edge, height: Self.edge)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let s = items.first, let from = Int(s), from != index else { return false }
            onMove(from, index)
            return true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("FrameRow.\(frame.id.uuidString)")
        .accessibilityLabel(showsCustomName ? "Frame \(index + 1), \(frame.name)" : "Frame \(index + 1)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Duplicate") { onDuplicate() }
        .accessibilityAction(named: "Rename") { onRename() }
        .accessibilityAction(named: "Delete") { onDelete() }
    }
}
