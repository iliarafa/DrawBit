import SwiftUI

/// In-app help reference. Pushed onto the gallery's `NavigationStack` from
/// the `info` button in the `GALLERY` header. Pure static content — no
/// environment dependencies.
///
/// Layout is a vertical stack of six cards, one per topic. Each card
/// carries a single SF Symbol icon, a pixel-font title, and a tight 1–2
/// sentence blurb — tuned for scannability over completeness. Pixel font
/// (Press Start 2P) is a poor match for long-form body copy, so this
/// screen keeps every card's body short by design.
///
/// Mirrors `FMScreen`'s chrome: custom topBar with a `chevron + GALLERY`
/// back chip, centered title, dark background, scrollable body. Section
/// identifiers go on the title `Text` of each card so UI tests can
/// confirm every section renders; never on a container view, to avoid
/// the descendant-propagation pitfall called out in the FM track list.
struct HelpScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 14) {
                    helpCard(
                        icon: "pencil.tip",
                        title: "TOOLS",
                        id: "Help.section.tools",
                        body: "Pencil, eraser, fill, swap, pick, laso. Tap a tool in the bottom bar to switch."
                    )
                    helpCard(
                        icon: "square.grid.3x3",
                        title: "CANVAS",
                        id: "Help.section.canvas",
                        body: "Pinch to zoom, two-finger drag to pan or rotate. Pixels never move — exports stay upright and crisp."
                    )
                    helpCard(
                        icon: "square.stack.3d.up.fill",
                        title: "LAYERS",
                        id: "Help.section.layers",
                        body: "Tap LAYERS in the editor top bar. Add, hide, lock, or reorder. The top layer sits on top of the canvas."
                    )
                    helpCard(
                        icon: "play.rectangle.fill",
                        title: "ANIMATION",
                        id: "Help.section.animation",
                        body: "Tap ANIMATE for the frames strip. Each frame keeps its own layers. Play, pick FPS, onion-skin to align."
                    )
                    helpCard(
                        icon: "square.and.arrow.up",
                        title: "EXPORT",
                        id: "Help.section.export",
                        body: "PNG for single frames. GIF, APNG, or sprite sheet for animations. Pick a scale, share."
                    )
                    helpCard(
                        icon: "dot.radiowaves.left.and.right",
                        title: "DRAWBIT FM",
                        id: "Help.section.fm",
                        body: "The tile at the bottom-left of the gallery plays a bundled station. Tap it to open the track list."
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
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

    // MARK: - Card

    /// One topic card: a 40pt SF Symbol icon on the left, a pixel-font
    /// title and a short body stacked on the right. The accessibility
    /// identifier lives on the title `Text` only — never on the container
    /// — to keep per-section ids queryable by `XCUITest`.
    @ViewBuilder
    private func helpCard(icon: String, title: String, id: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 44, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.pixel(12))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier(id)
                Text(body)
                    .font(.pixel(9))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
