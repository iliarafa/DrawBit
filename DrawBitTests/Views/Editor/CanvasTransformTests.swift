import XCTest
import CoreGraphics
@testable import DrawBit

/// `canvasToScreenTransform` maps a point in canvas-local (base, 1×) coordinates to its
/// on-screen position under the editor's view transform (scale / rotation / translation).
/// It must reproduce *exactly* the composite that `CanvasView` applies to the pixel image
/// (`.scaleEffect`/`.rotationEffect`/`.offset` about the viewport centre) — and equivalently
/// the inverse of `CanvasHostView.pixelCoord(for:)` — so the redrawn grid stays pixel-locked
/// to the art. These asserts pin that registration contract.
final class CanvasTransformTests: XCTestCase {
    private let base = CGSize(width: 768, height: 432)      // a 256×144 canvas at perPixel=3
    private let viewport = CGSize(width: 1366, height: 1024)
    private let acc: CGFloat = 0.0001

    private func center(_ s: CGSize) -> CGPoint { CGPoint(x: s.width / 2, y: s.height / 2) }

    /// The canvas centre always maps to the viewport centre + translation, for *any* scale and
    /// rotation (scaling/rotation are anchored at the centre, so the centre is their fixed point).
    func testCenterMapsToViewportCenterPlusTranslation() {
        let translation = CGSize(width: 40, height: -25)
        let t = canvasToScreenTransform(base: base, viewport: viewport,
                                        scale: 7.5, rotation: 1.1, translation: translation)
        let mapped = center(base).applying(t)
        XCTAssertEqual(mapped.x, viewport.width / 2 + translation.width, accuracy: acc)
        XCTAssertEqual(mapped.y, viewport.height / 2 + translation.height, accuracy: acc)
    }

    /// Identity view transform: the base top-left corner sits at viewport-centre − base/2.
    func testIdentityCornerIsCenteredFrame() {
        let t = canvasToScreenTransform(base: base, viewport: viewport,
                                        scale: 1, rotation: 0, translation: .zero)
        let corner = CGPoint(x: 0, y: 0).applying(t)
        XCTAssertEqual(corner.x, viewport.width / 2 - base.width / 2, accuracy: acc)
        XCTAssertEqual(corner.y, viewport.height / 2 - base.height / 2, accuracy: acc)
    }

    /// A pure zoom doubles a corner's offset from the centre (the grid grows about the centre).
    func testPureScaleDoublesCornerOffset() {
        let t1 = canvasToScreenTransform(base: base, viewport: viewport,
                                         scale: 1, rotation: 0, translation: .zero)
        let t2 = canvasToScreenTransform(base: base, viewport: viewport,
                                         scale: 2, rotation: 0, translation: .zero)
        let c = center(viewport)
        let off1 = CGPoint(x: 0, y: 0).applying(t1)
        let off2 = CGPoint(x: 0, y: 0).applying(t2)
        XCTAssertEqual(off2.x - c.x, 2 * (off1.x - c.x), accuracy: acc)
        XCTAssertEqual(off2.y - c.y, 2 * (off1.y - c.y), accuracy: acc)
    }

    /// A 90° rotation turns an x-axis offset into a y-axis offset (axes swap about the centre).
    func testNinetyDegreeRotationSwapsAxes() {
        let d: CGFloat = 100
        let t = canvasToScreenTransform(base: base, viewport: viewport,
                                        scale: 1, rotation: .pi / 2, translation: .zero)
        // A point offset (+d, 0) from the canvas centre.
        let p = CGPoint(x: base.width / 2 + d, y: base.height / 2).applying(t)
        let c = center(viewport)
        XCTAssertEqual(p.x - c.x, 0, accuracy: acc)        // x-offset gone
        XCTAssertEqual(abs(p.y - c.y), d, accuracy: acc)   // ...became a y-offset of magnitude d
    }

    /// Registration check: the transform is the exact inverse of the gesture's screen→pixel
    /// mapping. Round-trip a base point through `canvasToScreenTransform` then back through the
    /// inverse and land where we started.
    func testRoundTripThroughInverse() {
        let t = canvasToScreenTransform(base: base, viewport: viewport,
                                        scale: 6, rotation: 0.3,
                                        translation: CGSize(width: 12, height: -8))
        let p = CGPoint(x: 123, y: 211)
        let back = p.applying(t).applying(t.inverted())
        XCTAssertEqual(back.x, p.x, accuracy: 0.001)
        XCTAssertEqual(back.y, p.y, accuracy: 0.001)
    }

    // MARK: - gridLineAlpha (fade the interior grid when zoomed out)

    func testGridHiddenWhenCellsTiny() {
        XCTAssertEqual(gridLineAlpha(screenCellPoints: 3), 0, accuracy: acc)   // large canvas at fit
        XCTAssertEqual(gridLineAlpha(screenCellPoints: 4), 0, accuracy: acc)   // at the low edge
        XCTAssertEqual(gridLineAlpha(screenCellPoints: 0), 0, accuracy: acc)
    }

    func testGridFullOnlyWhenCellsLarge() {
        XCTAssertEqual(gridLineAlpha(screenCellPoints: 20), 1, accuracy: acc)  // at the high edge (was 9)
        XCTAssertEqual(gridLineAlpha(screenCellPoints: 27), 1, accuracy: acc)  // 32-canvas at fit, full
    }

    func testGridFadesGraduallySoDenseCanvasesStayCalm() {
        XCTAssertEqual(gridLineAlpha(screenCellPoints: 12), 0.5, accuracy: acc)     // midpoint of 4…20
        XCTAssertEqual(gridLineAlpha(screenCellPoints: 15), 0.6875, accuracy: acc)  // ~96×54 at fit: dimmed, not full
        XCTAssertEqual(gridLineAlpha(screenCellPoints: 9), 0.3125, accuracy: acc)   // dense: well below full now
    }
}
