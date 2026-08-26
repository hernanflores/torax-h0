import XCTest
@testable import MIDI

final class MIDIPackageTests: XCTestCase {
    func testPackageIsReachable() {
        XCTAssertEqual(MIDIPackage.name, "MIDI")
    }
}
