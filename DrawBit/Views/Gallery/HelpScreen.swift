import SwiftUI

/// In-app help reference. Pushed onto the gallery's `NavigationStack` from the
/// `info` button in the `GALLERY` header. Pure static content — no environment
/// dependencies.
///
/// Layout is a 2-column grid of compact icon+title tiles, vertically centered
/// between the back chip and a version footer. Tapping a tile reveals that
/// topic's instructions *in place* — the text replaces the icon+title within the
/// tile's own footprint; the row-mate stays put (no full-row expansion).
/// Single-selection: tapping again, or another tile, collapses / switches. The
/// ANIMATION tile reuses the editor's ANIMATE play sprite
/// (`PixelArtIcon.playTriangle`) so it reads as the same control.
///
/// Each section's accessibility identifier lives on its title `Text` (shown by
/// default, before any tile is tapped) so UI tests can confirm every section
/// renders. Tiles use `.onTapGesture` (not `Button`) so those titles stay
/// queryable as `staticTexts`.
struct HelpScreen: View {
    @Environment(\.dismiss) private var dismiss
    /// The single expanded topic, if any. Tapping a tile extends it to span the
    /// full row; tapping again (or another tile) collapses / switches.
    @State private var expanded: String?

    /// Shared tile height for both the collapsed and expanded states. The expanded
    /// container is the same height, placed over the tapped tile's row.
    private static let tileHeight: CGFloat = 176
    /// Vertical gap between grid rows — also the row pitch (tileHeight + rowGap) used to
    /// offset the expanded overlay onto the right row.
    private static let rowGap: CGFloat = 16

    /// A grid for the CANVAS tile — three vertical and three horizontal lines at
    /// slightly uneven spacing (graph-paper, not the keypad-like 3×3 dots).
    private static let gridLines: [String] = [
        ".#...#..#..",
        ".#...#..#..",
        "###########",
        ".#...#..#..",
        ".#...#..#..",
        "###########",
        ".#...#..#..",
        ".#...#..#..",
        ".#...#..#..",
        "###########",
        ".#...#..#..",
    ]

    /// Two beamed eighth notes (♫) for the DRAWBIT FM tile — a pixel sprite (like
    /// the ANIMATION tile) so it matches the app's pixel aesthetic. Help-page only.
    private static let eighthNotes: [String] = [
        "...........",
        "...######..",
        "...######..",
        "...#....#..",
        "...#....#..",
        "...#....#..",
        "...#....#..",
        "...#....#..",
        ".###..###..",
        ".##...##...",
        "...........",
    ]

    /// A pixel "image" sprite for the TRACE tile — a faithful copy of the SF
    /// `photo` glyph it replaces: a landscape photo frame (13×10, so it renders
    /// wider than tall), a small white-square sun top-left, and TWO mountains (a
    /// lower left peak, a taller right peak). Drawn as hard pixels so it matches
    /// the app's aesthetic rather than the SF symbol's curves.
    private static let traceImage: [String] = [
        "#############",
        "#...........#",
        "#.##........#",
        "#.##........#",
        "#.......#...#",
        "#......###..#",
        "#...#.#####.#",
        "#..##########",
        "#.###########",
        "#############",
    ]

    /// A pixel toolbox for the TOOLS tile — a carry handle, a lidded box, and a
    /// front clasp. Hard pixels, replacing the ambiguous SF `pencil.tip` glyph.
    private static let toolbox: [String] = [
        "....#####....",
        "....#...#....",
        "....#...#....",
        ".###########.",
        ".#.........#.",
        ".###########.",
        ".#.........#.",
        ".#...###...#.",
        ".#.........#.",
        ".###########.",
    ]

    private enum HelpIcon {
        case symbol(String)
        case pixel([String])
        /// A template image asset (e.g. the editor's "LayersIcon").
        case asset(String)
        /// The editor's vector share/export glyph, reused verbatim.
        case shareGlyph
        /// The COLOURS icon — three square swatches in the logo's red / green /
        /// blue, the one icon that carries colour so the tile illustrates itself.
        case colourSwatches
        /// The GALLERY icon — a 2×2 grid of solid white squares, square corners,
        /// each the same size as a COLOURS swatch.
        case galleryGrid
    }

    private struct HelpTopic: Identifiable {
        /// Doubles as the title's accessibility identifier.
        let id: String
        let icon: HelpIcon
        let title: String
        let body: String
    }

    private static let topics: [HelpTopic] = [
        HelpTopic(id: "Help.section.gallery", icon: .galleryGrid, title: "GALLERY",
                  body: "Your draws live here. Tap one to open it. Press and hold a tile to duplicate or delete it."),
        HelpTopic(id: "Help.section.colours", icon: .colourSwatches, title: "COLOURS",
                  body: "Tap the colour swatch to open the picker. Pick from built-in palettes — DB32, PICO-8, Sweetie 16, Game Boy — or mix your own by hex, spectrum or sliders. Save custom palettes; your recent colours are kept."),
        HelpTopic(id: "Help.section.tools", icon: .pixel(Self.toolbox), title: "TOOLS",
                  body: "Pencil, eraser, fill, swap, pick, laso — tap one in the bottom bar to switch. Mirror reflects every stroke across the vertical centre. Undo and redo sit at the bar's end."),
        HelpTopic(id: "Help.section.canvas", icon: .pixel(Self.gridLines), title: "CANVAS",
                  body: "Tap + to start a new draw — pick a preset size or set your own from 8 to 256. Then pinch to zoom, two-finger drag to pan or rotate. Pixels never move, so exports stay upright and crisp."),
        HelpTopic(id: "Help.section.layers", icon: .asset("LayersIcon"), title: "LAYERS",
                  body: "Tap LAYERS in the editor top bar to add, hide, or lock. Press and drag a layer by its thumbnail to reorder. The top layer sits above the canvas."),
        HelpTopic(id: "Help.section.trace", icon: .pixel(Self.traceImage), title: "TRACE",
                  body: "Add a photo to trace over from the foot of the Layers panel. It sits dimmed behind your pixels — set its fade, hide it, or remove it any time. It never appears in exports."),
        HelpTopic(id: "Help.section.animation", icon: .pixel(PixelArtIcon.playTriangle), title: "ANIMATION",
                  body: "Tap ANIMATE for the frames strip. Add a blank frame, duplicate, delete, or drag to reorder — each keeps its own layers. ONION fades the previous frame to help you line things up. Pick an FPS, then Play."),
        HelpTopic(id: "Help.section.export", icon: .shareGlyph, title: "EXPORT",
                  body: "PNG: one still frame. GIF: animation, plays anywhere but only 256 colours. APNG: animation in full colour. Sprite: every frame in one image. Then pick a scale and share."),
        HelpTopic(id: "Help.section.fm", icon: .pixel(Self.eighthNotes), title: "DRAWBIT FM",
                  body: "A dedicated radio station playing original music composed by members of the development team. Tap the tile at the bottom-right of the gallery to tune in."),
        HelpTopic(id: "Help.section.about", icon: .symbol("info.circle"), title: "ABOUT",
                  body: "Nothing more to say really. We just needed an even number of tiles. Thank you."),
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
        Grid(horizontalSpacing: 16, verticalSpacing: Self.rowGap) {
            ForEach(Array(stride(from: 0, to: Self.topics.count, by: 2)), id: \.self) { start in
                let a = Self.topics[start]
                let b = start + 1 < Self.topics.count ? Self.topics[start + 1] : nil
                GridRow {
                    tileCell(a)
                    if let b { tileCell(b) }
                }
            }
        }
    }

    /// One grid cell: the topic's body text in place when selected, else the
    /// compact icon+title. Either way it fills exactly one column — no row
    /// spanning. The body assembles from pixel blocks on open (`openDissolve`);
    /// collapsing or switching is an instant cut (identity) so the next open's
    /// dissolve gets the full spotlight.
    @ViewBuilder
    private func tileCell(_ topic: HelpTopic) -> some View {
        if expanded == topic.id {
            bodyTile(topic).transition(.openDissolve).id("exp-\(topic.id)")
        } else {
            collapsedTile(topic).transition(.identity).id("col-\(topic.id)")
        }
    }

    /// Toggle the expanded topic. The pixel-dissolve transition only fires inside an
    /// animation transaction, so a `nil` animation under UI test makes it instant.
    private func toggle(_ id: String) {
        let anim: Animation? = UITestSupport.isRunning ? nil : .easeOut(duration: 0.55)
        withAnimation(anim) {
            expanded = (expanded == id) ? nil : id
        }
    }

    /// Compact resting tile: icon over the title. Tapping extends it to a full row.
    private func collapsedTile(_ topic: HelpTopic) -> some View {
        VStack(spacing: 12) {
            icon(topic.icon, tinted: false)
            Text(topic.title)
                .font(.pixel(11))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier(topic.id)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.tileHeight)
        .padding(.horizontal, 16)
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .hoverPop(scale: 1.08, lift: 4, shadow: false)
        .contentShape(Rectangle())
        .onTapGesture { toggle(topic.id) }
    }

    /// Selected state: the instructions in place of the icon+title, within the
    /// tile's own single-column footprint (same 176pt box, half-panel width).
    private func bodyTile(_ topic: HelpTopic) -> some View {
        Text(topic.body)
            .font(.pixelBody(20))
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.leading)
            .lineSpacing(4)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.tileHeight)
            .background(Color(white: 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { toggle(topic.id) }
    }

    @ViewBuilder
    private func icon(_ icon: HelpIcon, tinted: Bool) -> some View {
        let color = tinted ? Color.toolSelected : Color.white.opacity(0.9)
        // LAYERS/EXPORT/FM carry internal margin (the sprite fills only part of its box),
        // so they get larger render sizes to read at the same visual size as TOOLS /
        // CANVAS / ANIMATION, which fill their frames. TRACE and TOOLS are wide,
        // short sprites, so they're rendered a touch larger to match the others.
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name).font(.system(size: 34, weight: .regular))
            case .pixel(let pattern):
                PixelArtIcon(pattern: pattern,
                             size: pattern == Self.eighthNotes ? 42
                                 : ((pattern == Self.traceImage || pattern == Self.toolbox) ? 40 : 34))
            case .asset(let name):
                Image(name).resizable().interpolation(.none).antialiased(false)
                    .frame(width: 42, height: 42)
            case .shareGlyph:
                ShareGlyph().frame(width: 40, height: 40)
            case .colourSwatches:
                ColourSwatchesIcon().frame(width: 40, height: 40)
            case .galleryGrid:
                GalleryGridIcon().frame(width: 40, height: 40)
            }
        }
        .foregroundStyle(color)
        .frame(height: 44)
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

/// The COLOURS tile icon: three flat square swatches in the DrawBit logo's
/// red / green / blue, sat side by side. It is the only icon on the otherwise
/// monochrome Help screen that carries colour — so the COLOURS tile illustrates
/// itself. Square corners, no outline: matches the app's pixel aesthetic. The
/// three swatches mirror the logo's three stripes (values sampled from `AppLogo`).
private struct ColourSwatchesIcon: View {
    private static let swatches: [Color] = [
        Color(red: 1.0,        green: 0.0,         blue: 6.0 / 255),    // #FF0006
        Color(red: 74.0 / 255, green: 189.0 / 255, blue: 67.0 / 255),  // #4ABD43
        Color(red: 64.0 / 255, green: 157.0 / 255, blue: 1.0),         // #409DFF
    ]

    var body: some View {
        Canvas { ctx, size in
            let gap = size.width * 0.06
            let side = (size.width - gap * 2) / 3
            let y = (size.height - side) / 2
            for (i, color) in Self.swatches.enumerated() {
                let x = CGFloat(i) * (side + gap)
                ctx.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(color))
            }
        }
    }
}

/// The GALLERY tile icon: a 2×2 grid of solid white squares. Square corners (the
/// app's pixel aesthetic) and each square the same size as a `ColourSwatchesIcon`
/// swatch — `side` and `gap` use the identical fractions so the two icons read
/// as the same building block.
private struct GalleryGridIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let gap = size.width * 0.06
            let side = (size.width - gap * 2) / 3   // matches a COLOURS swatch
            let block = side * 2 + gap
            let ox = (size.width - block) / 2
            let oy = (size.height - block) / 2
            for row in 0..<2 {
                for col in 0..<2 {
                    let x = ox + CGFloat(col) * (side + gap)
                    let y = oy + CGFloat(row) * (side + gap)
                    ctx.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(.white))
                }
            }
        }
    }
}
// PixelDissolve / PixelDissolveModifier / AnyTransition.openDissolve now live in
// DrawBit/Views/Support/PixelDissolve.swift so the launch intro can reuse them.
