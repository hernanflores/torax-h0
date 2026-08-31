import XCTest
@testable import Engine

/// Ver la nota de `PatternTests` sobre la ambigüedad del nombre en los targets
/// de test.
private typealias Pattern = Engine.Pattern

/// Tests del canal MIDI como dato del Track.
///
/// **Dieciséis Tracks y dieciséis canales es la correspondencia que no hay que
/// explicar.** Sin ella los dieciséis sonarían al mismo instrumento y no habría
/// forma de juzgar nada en dispositivo.
final class TrackChannelTests: XCTestCase {

    // MARK: - El tipo

    func testAChannelIsOneToSixteen() {
        XCTAssertEqual(Channel.validRange, 1...16)
        for number in 1...16 {
            XCTAssertEqual(Channel(number)?.number, number)
        }
    }

    func testAChannelOutsideTheRangeDoesNotExist() {
        for number in [-1, 0, 17, 128, Int.max, Int.min] {
            XCTAssertNil(Channel(number), "\(number)")
        }
    }

    // MARK: - Track N en el canal N

    func testEachTrackStartsOnItsOwnChannel() {
        let pattern = Pattern()
        for index in 0..<16 {
            XCTAssertEqual(
                pattern.track(at: index)?.channel.number, index + 1, "Track \(index + 1)")
        }
    }

    /// Y el Pattern inicial sigue la misma regla: el Track 1 emite por el canal
    /// 1, que es por donde emitía la app con un Track solo.
    func testTheInitialPatternFollowsTheSameRule() {
        XCTAssertEqual(Pattern.initial.track(at: 0)?.channel.number, 1)
        for index in 1..<16 {
            XCTAssertEqual(Pattern.initial.track(at: index)?.channel.number, index + 1)
        }
    }

    // MARK: - Se puede cambiar

    func testChangingTheChannelOfATrackLeavesTheOthersAlone() {
        let pattern = Pattern()
        let moved = pattern.track(at: 3)!.on(Channel(10)!)
        let updated = pattern.replacing(moved, at: 3)

        XCTAssertEqual(updated.track(at: 3)?.channel.number, 10)
        for other in 0..<16 where other != 3 {
            XCTAssertEqual(
                updated.track(at: other)?.channel.number, other + 1, "Track \(other + 1)")
        }
    }

    /// **Dos Tracks pueden compartir canal.** Dos capas rítmicas sobre el mismo
    /// sinte es un caso real, no un error que haya que impedir.
    func testTwoTracksCanShareAChannel() {
        var pattern = Pattern()
        pattern = pattern.replacing(pattern.track(at: 0)!.on(Channel(5)!), at: 0)
        pattern = pattern.replacing(pattern.track(at: 1)!.on(Channel(5)!), at: 1)

        XCTAssertEqual(pattern.track(at: 0)?.channel.number, 5)
        XCTAssertEqual(pattern.track(at: 1)?.channel.number, 5)
    }

    /// Cambiar el canal no toca el material: es configuración, no contenido.
    func testChangingTheChannelKeepsEverythingElse() {
        let track = Pattern.initial.track(at: 0)!
        let moved = track.on(Channel(9)!)

        XCTAssertEqual(moved.shape, track.shape)
        XCTAssertEqual(moved.pool, track.pool)
        XCTAssertEqual(moved.groove, track.groove)
    }

    // MARK: - La red de tiempo real

    /// El canal viaja dentro del snapshot, así que tiene que ser trivial como
    /// todo lo demás.
    func testTheChannelKeepsTheValuesTrivial() {
        XCTAssertTrue(_isPOD(Channel.self), "Channel dejó de ser trivial")
        XCTAssertTrue(_isPOD(Track.self), "Track dejó de ser trivial")
        XCTAssertTrue(_isPOD(Pattern.self), "Pattern dejó de ser trivial")
    }
}
