import XCTest
@testable import Engine

final class EngineTests: XCTestCase {
    func testSchemaVersionIsDeclared() {
        XCTAssertEqual(EngineSchema.schemaVersion, 1)
    }
}
