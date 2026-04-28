import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class PencilAvailability {
    var isPencilAvailable: Bool

    init() {
        self.isPencilAvailable = false
    }

    #if canImport(UIKit)
    func updateFromTouch(_ touch: UITouch) {
        if touch.type == .pencil {
            isPencilAvailable = true
        }
    }
    #endif
}
