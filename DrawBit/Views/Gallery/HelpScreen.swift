import SwiftUI

/// In-app help reference. Pushed onto the gallery's `NavigationStack` from the
/// `info` button in the `GALLERY` header. Pure static content — no environment
/// dependencies.
///
/// Layout is a 2-column grid of icon tiles, one per topic, vertically centered
/// between the back chip and a version footer. Each tile is a button: tapping it
/// swaps its label in place from the topic title to the topic's instructions
/// (and back). The ANIMATION tile reuses the editor's ANIMATE play sprite
/// (`PixelArtIcon.playTriangle`) so it reads as the same control.
///
/// Each section's accessibility identifier lives on its title `Text` (shown by
/// default, before any tile is tapped) so UI tests can confirm every section
/// renders. Tiles use `.onTapGesture` (not `Button`) so those titles stay
/// queryable as `staticTexts`.
struct HelpScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<String> = []

    private enum HelpIcon {
        case symbol(String)
        case pixel([String])
    }

    private struct HelpTopic: Identifiable {
        /// Doubles as the title's accessibility identifier.
        let id: String
        let icon: HelpIcon
        let title: String
        let body: String
    }

    private static let topics: [HelpTopic] = [
        HelpTopic(id: "Help.section.tools", icon: .symbol("pencil.tip"), title: "TOOLS",
                  body: "Pencil, eraser, fill, swap, pick, laso. Tap a tool in the bottom bar to switch."),
        HelpTopic(id: "Help.section.canvas", icon: .symbol("square.grid.3x3"), title: "CANVAS",
                  body: "Pinch to zoom, two-finger drag to pan or rotate. Pixels never move — exports stay upright and crisp."),
        HelpTopic(id: "Help.section.layers", icon: .symbol("square.stack.3d.up.fill"), title: "LAYERS",
                  body: "Tap LAYERS in the editor top bar to add, hide, or lock. Press and drag a layer by its thumbnail to reorder. The top layer sits above the canvas."),
        HelpTopic(id: "Help.section.animation", icon: .pixel(PixelArtIcon.playTriangle), title: "ANIMATION",
                  body: "Tap ANIMATE for the frames strip. Each frame keeps its own layers. Play, pick FPS, onion-skin to align."),
        HelpTopic(id: "Help.section.export", icon: .symbol("square.and.arrow.up"), title: "EXPORT",
                  body: "PNG: one still frame. GIF: animation, plays anywhere but only 256 colours. APNG: animation in full colour. Sprite: every frame in one image. Then pick a scale and share."),
        HelpTopic(id: "Help.section.fm", icon: .symbol("dot.radiowaves.left.and.right"), title: "DRAWBIT FM",
                  body: "The tile at the bottom-left of the gallery plays a bundled station. Tap it to open the track list."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            backRow

            Spacer(minLength: 24)

            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("HELP")
                        .font(.pixel(18))
                        .foregroundStyle(.white)
                    Text("TAP A TOPIC FOR DETAILS")
                        .font(.pixel(8))
                        .foregroundStyle(.white.opacity(0.4))
                }
                topicGrid
                    .padding(.horizontal, 20)
            }

            Spacer(minLength: 24)

            footer
        }
        .background(Color(white: 0.10).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Grid

    private var topicGrid: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            ForEach(Array(stride(from: 0, to: Self.topics.count, by: 2)), id: \.self) { start in
                GridRow {
                    tile(Self.topics[start])
                    if start + 1 < Self.topics.count {
                        tile(Self.topics[start + 1])
                    }
                }
            }
        }
    }

    /// One topic tile. Default: icon over the title. Tapped: icon over the
    /// instructions (the title `Text` is swapped out). Fixed height so the swap
    /// never reflows the grid. The active tile picks up the `toolSelected` accent.
    private func tile(_ topic: HelpTopic) -> some View {
        let isOpen = expanded.contains(topic.id)
        return VStack(spacing: 12) {
            icon(topic.icon, tinted: isOpen)

            if isOpen {
                Text(topic.body)
                    .font(.pixel(8))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .minimumScaleFactor(0.7)
            } else {
                Text(topic.title)
                    .font(.pixel(11))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier(topic.id)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .padding(.horizontal, 16)
        .background(Color(white: 0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isOpen ? Color.toolSelected : Color.white.opacity(0.12),
                        lineWidth: isOpen ? 1 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            if isOpen { expanded.remove(topic.id) } else { expanded.insert(topic.id) }
        }
    }

    @ViewBuilder
    private func icon(_ icon: HelpIcon, tinted: Bool) -> some View {
        let color = tinted ? Color.toolSelected : Color.white.opacity(0.9)
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(color)
                .frame(height: 40)
        case .pixel(let pattern):
            PixelArtIcon(pattern: pattern, size: 34)
                .foregroundStyle(color)
                .frame(height: 40)
        }
    }

    // MARK: - Chrome

    private var backRow: some View {
        HStack {
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var footer: some View {
        Text("DRAWBIT v\(appVersion)")
            .font(.pixel(8))
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
