import XCTest
@testable import LLMCore

final class LLMCoreTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(LLMCore.version.isEmpty)
    }
}
