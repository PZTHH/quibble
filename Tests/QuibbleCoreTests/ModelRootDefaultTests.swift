import XCTest
@testable import QuibbleCore

final class ModelRootDefaultTests: XCTestCase {
    private let fallback = "/Users/example/Library/Application Support/Quibble/Models"

    func testDevelopmentBuildKeepsTheCheckoutFolder() {
        XCTAssertEqual(ModelRootDefault.path(configured: "/Users/example/Projects/quibble/Models", fallback: fallback),
                       "/Users/example/Projects/quibble/Models")
    }

    func testDistributionBuildFallsBackWhenTheSettingIsCleared() {
        // A cleared build setting reaches the bundle as an empty string, not a missing key.
        XCTAssertEqual(ModelRootDefault.path(configured: "", fallback: fallback), fallback,
                       "A shipped app must not resolve an empty path against its working directory")
        XCTAssertEqual(ModelRootDefault.path(configured: "   \n ", fallback: fallback), fallback)
    }

    func testMissingKeyFallsBack() {
        XCTAssertEqual(ModelRootDefault.path(configured: nil, fallback: fallback), fallback)
    }
}
