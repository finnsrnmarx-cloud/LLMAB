import XCTest
@testable import UIKitOmega

final class UIKitOmegaTests: XCTestCase {

    func testMarkIsLowercaseOmega() {
        XCTAssertEqual(UIKitOmega.mark, "ω")
        XCTAssertEqual(UIKitOmega.mark.unicodeScalars.first?.value, 0x03C9)
    }

    func testTimingConstantsAreReasonable() {
        XCTAssertGreaterThan(UIKitOmega.spinDurationSeconds, 0)
        XCTAssertGreaterThan(UIKitOmega.auroraShiftSeconds, UIKitOmega.spinDurationSeconds,
                             "aurora hue drift should be slower than the spinner rotation")
    }

    func testBundlePrefixNamespace() {
        XCTAssertTrue(UIKitOmega.bundlePrefix.hasPrefix("org.llmab"))
    }
}
