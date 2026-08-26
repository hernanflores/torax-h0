import XCTest
@testable import Engine

final class EngineTests: XCTestCase {
    func testSchemaVersionIsDeclared() {
        XCTAssertEqual(Engine.schemaVersion, 1)
    }
}
