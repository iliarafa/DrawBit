import SwiftUI

/// In-app help reference. Pushed onto the gallery's `NavigationStack` from
/// the `?` button in the `GALLERY` header. Pure static content — no
/// environment dependencies — so it stays fast and trivially testable.
///
/// Mirrors `FMScreen`'s shape: custom topBar with a `chevron + GALLERY`
/// back chip and a centered title, dark background, scrollable body. Each
/// section is a private computed view so the `body` reads as a table of
/// contents. Section headings have per-section accessibility identifiers
/// so UI tests can confirm they all render; never attach an identifier to
/// a container — it propagates to every descendant and clobbers per-child
/// ids (the same warning the FM track list and old `RadioStrip` carry).
struct HelpScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    toolsSection
                    sectionDivider
                    canvasSection
                    sectionDivider
                    layersSection
                    sectionDivider
                    animationSection
                    sectionDivider
                    exportSection
                    sectionDivider
                    fmSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .background(Color(white: 0.10).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("GALLERY").font(.pixel(11))
                }
            }
            .foregroundStyle(.white)
            .accessibilityIdentifier("Gallery")

            Spacer()

            Text("HELP")
                .font(.pixel(12))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            // Balances the leading button's width so the title is truly centered.
            Color.clear.frame(width: 80, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: - Section building blocks

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    @ViewBuilder
    private func sectionHeading(_ title: String, id: String) -> some View {
        Text(title)
            .font(.pixel(14))
            .foregroundStyle(.white)
            .accessibilityIdentifier(id)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.pixel(8))
            .foregroundStyle(.white.opacity(0.85))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("TOOLS", id: "Help.section.tools")
            paragraph("PENCIL paints one pixel at a time. Drag to draw a line — fast strokes are filled in so you never get gaps.")
            paragraph("ERASER writes transparency. Erased pixels are gone, not painted white. The checkered pattern in the export preview shows what's transparent.")
            paragraph("FILL replaces a connected region of the same color with the current color. Tap a pixel and every neighbour of the same colour flips with it.")
            paragraph("SWAP recolours every pixel of one colour to another across the whole layer. Pick a source colour, pick a target, swap.")
            paragraph("PICK is an eyedropper. Tap any pixel to make its colour the active one.")
            paragraph("LASO selects a rectangular region. The selected pixels lift off the layer and float — drag them anywhere, then tap outside to drop them in their new spot.")
            paragraph("Under the tools, the bottom bar has UNDO and REDO, a CLEAR button for the current layer, and a row of recent colours. Tap + on the colour row to open the full picker.")
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("CANVAS & TRANSFORM", id: "Help.section.canvas")
            paragraph("Canvas sizes are 16×16, 32×32, 64×64, and 128×128. Pick one when you create a new piece. The size is fixed for the life of the piece — pixels are the unit, not points.")
            paragraph("Pinch with two fingers to zoom in or out — useful for detail work. The view zooms from 0.25× to 40×.")
            paragraph("Two-finger drag pans the view. Two-finger rotate spins it; release near upright and it snaps back to 0° so straightening is forgiving.")
            paragraph("Double-tap with two fingers to reset zoom, rotation, and pan to the home view.")
            paragraph("Important: panning, zooming, and rotating only change what you see. The stored pixels never move. Exports are always upright, axis-aligned, and crisp at every zoom level.")
        }
    }

    private var layersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("LAYERS", id: "Help.section.layers")
            paragraph("Tap the LAYERS button in the editor's top-right to open the layer panel.")
            paragraph("Layers stack from bottom to top — the topmost layer in the panel sits visually on top of the canvas. Anything you draw goes onto the highlighted layer.")
            paragraph("Use + to add a new layer, the duplicate icon to copy the active one, and the trash icon to delete it. Empty layers delete instantly; layers with pixels ask for confirmation first.")
            paragraph("The eye icon hides a layer without deleting it. The lock icon prevents drawing on a layer — tap a locked layer to see a quick flash that tells you why nothing's happening.")
            paragraph("Long-press a layer to enter reorder mode, then drag rows to restack. Long-press a layer's name to rename it (up to 32 characters).")
        }
    }

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("ANIMATION", id: "Help.section.animation")
            paragraph("Tap ANIMATE in the editor's top bar to reveal the frames strip across the bottom of the canvas.")
            paragraph("A piece can have up to 60 frames, and each frame has its own full layer stack. Frames and layers are independent — adding a layer adds it only to the current frame.")
            paragraph("ADD at the end of the strip appends a new blank frame. Drag a frame left or right to reorder. Right-tap (or long-press) a frame for options including delete.")
            paragraph("ONION turns on onion-skinning — a faded ghost of the previous frame shows under the current one, so you can line up movement frame-to-frame.")
            paragraph("PLAY previews the animation in place. The FPS pill changes the playback speed; pick 4, 8, 12, 24, 30, or 60 frames per second.")
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("EXPORT", id: "Help.section.export")
            paragraph("Tap the share icon in the editor top bar to export. The sheet shows the formats available for your piece.")
            paragraph("Single-frame pieces export as a PNG of the active frame. Multi-frame pieces add GIF (animated), APNG (animated, smaller), and SPRITE SHEET (all frames tiled in one image) on top of the PNG option.")
            paragraph("Pick a scale: 1×, 2×, 4×, 8×, or 16×. Every pixel becomes a clean square block of pixels at the new size — no blurring. Larger scales make bigger files; choose based on where the image is going (the web, a print, a sprite engine).")
            paragraph("If a scale would make the export too large to safely encode, the tile shows TOO BIG and is disabled. Pick a smaller scale or a different format.")
        }
    }

    private var fmSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("DRAWBIT FM", id: "Help.section.fm")
            paragraph("The DRAWBIT FM tile lives at the bottom-left of the gallery. It's a small bundled radio station — tap the big play button on the tile to start the music.")
            paragraph("Music keeps playing while you draw, switch pieces, or navigate around. The transport keeps working in the lock-screen Now Playing controls too.")
            paragraph("Tap anywhere else on the tile to open the full FM screen. There you can see all the tracks in the station, scrub through the current one, skip back and forward, or tap any track to jump to it.")
        }
    }
}
