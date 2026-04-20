import XCTest
@testable import Bitme

final class AppIconTests: XCTestCase {
    func testInfoPlistDeclaresAppIcon() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(
            info["CFBundleIconName"] as? String,
            "AppIcon",
            "CFBundleIconName must be 'AppIcon' so iOS picks the compiled catalog icon."
        )
    }

    func testCompiledAssetCatalogIsBundled() {
        XCTAssertNotNil(
            Bundle.main.url(forResource: "Assets", withExtension: "car"),
            "Assets.car must be compiled and bundled — that's where the AppIcon variants live."
        )
    }

    func testIPadIconFilesAreEmittedFromCatalog() {
        // When ASSETCATALOG_COMPILER_APPICON_NAME is set and the catalog has an
        // AppIcon set, Xcode emits these derivatives alongside the compiled .car.
        XCTAssertNotNil(
            Bundle.main.url(forResource: "AppIcon76x76@2x~ipad", withExtension: "png"),
            "AppIcon76x76@2x~ipad.png must be emitted for iPad Home Screen."
        )
    }
}
