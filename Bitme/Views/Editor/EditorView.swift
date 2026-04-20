import SwiftUI
import SwiftData
import UIKit

struct EditorView: View {
    let piece: Piece
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var state: EditorState
    @State private var pencilAvailability = PencilAvailability()
    @State private var recentHex: [String] = []
    @State private var showingSystemColorPicker = false
    @State private var showingShareSheet = false

    init(piece: Piece) {
        self.piece = piece
        self._state = State(initialValue: EditorState(piece: piece))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Color.white.opacity(0.08))
            CanvasView(
                state: state,
                pencilAvailability: pencilAvailability,
                onStrokePoint: { x, y in applyDrawPoint(x: x, y: y) },
                onStrokeBegin: { state.beginStrokeSnapshot() },
                onStrokeEnd: { commitStrokeAndSave() },
                onStrokeCancel: { state.cancelStroke() },
                onTap: { x, y in
                    state.beginStrokeSnapshot()
                    applyDrawPoint(x: x, y: y)
                    commitStrokeAndSave()
                }
            )
            Divider().overlay(Color.white.opacity(0.08))
            bottomBar
        }
        .background(Color(white: 0.10).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSystemColorPicker) {
            NavigationStack {
                SystemColorPicker(
                    initialColor: state.color,
                    onChange: { state.color = $0 }
                )
                .ignoresSafeArea(edges: [.bottom, .horizontal])
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("COLORS")
                            .font(.pixel(14))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSystemColorPicker = false
                        } label: {
                            Text("USE")
                                .font(.pixel(12))
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: showingSystemColorPicker) { _, isShowing in
            if !isShowing {
                addRecent(state.color.hex)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(piece: piece)
                .presentationDetents([.medium])
        }
        .onAppear {
            let repo = PieceRepository(context: modelContext)
            if let settings = try? repo.appSettings() {
                recentHex = settings.recentColors
            }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("GALLERY")
                        .font(.pixel(11))
                }
            }
            .accessibilityIdentifier("Gallery")
            Spacer()
            Text(piece.size.displayName)
                .font(.pixel(12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button {
                showingShareSheet = true
            } label: {
                Text("SHARE")
                    .font(.pixel(11))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 20) {
            ToolBar(state: state)
            Divider().frame(height: 36).overlay(Color.white.opacity(0.15))
            RecentColorsStrip(
                selectedColor: Binding(
                    get: { state.color },
                    set: { state.color = $0 }
                ),
                recentHex: $recentHex,
                onRequestColorPicker: { showingSystemColorPicker = true }
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(height: 72)
        .background(Color(white: 0.09))
    }

    // MARK: - Drawing actions

    private func applyDrawPoint(x: Int, y: Int) {
        switch state.tool {
        case .pencil:
            Pencil.paint(on: &state.grid, at: (x, y), color: state.color)
        case .eraser:
            Eraser.erase(on: &state.grid, at: (x, y))
        case .fill:
            Fill.fill(on: &state.grid, at: (x, y), with: state.color)
        case .eyedropper:
            if let picked = Eyedropper.pick(from: state.grid, at: (x, y)) {
                state.color = picked
            }
        }
    }

    private func commitStrokeAndSave() {
        state.commitStroke()
        let repo = PieceRepository(context: modelContext)
        try? repo.save(piece: piece, pixels: state.grid.data)
        // Pencil-only: record color into recents on stroke commit. Skip for eraser/eyedropper.
        if state.tool == .pencil || state.tool == .fill {
            addRecent(state.color.hex)
        }
    }

    private func addRecent(_ hex: String) {
        let repo = PieceRepository(context: modelContext)
        if let settings = try? repo.appSettings() {
            settings.addRecentColor(hex)
            recentHex = settings.recentColors
            try? modelContext.save()
        }
    }
}

private struct SystemColorPicker: UIViewControllerRepresentable {
    var initialColor: RGBA
    var onChange: (RGBA) -> Void

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let controller = UIColorPickerViewController()
        controller.supportsAlpha = false
        controller.selectedColor = UIColor(
            red: CGFloat(initialColor.r) / 255,
            green: CGFloat(initialColor.g) / 255,
            blue: CGFloat(initialColor.b) / 255,
            alpha: 1
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIColorPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        let parent: SystemColorPicker
        init(parent: SystemColorPicker) { self.parent = parent }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            if let rgba = RGBA(cgColor: viewController.selectedColor.cgColor) {
                parent.onChange(rgba)
            }
        }
    }
}
