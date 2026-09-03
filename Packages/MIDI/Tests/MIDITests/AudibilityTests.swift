import Engine
import XCTest
@testable import MIDI

/// Tests de la regla de audibilidad (FR2).
///
/// ```
/// audible(i) = !mute(i) && (soloMask == 0 || solo(i))
/// ```
///
/// **Es una regla corta con dos trampas.** La primera: sin ningún solo suenan
/// todos, y no ninguno — el solo solo significa algo cuando alguien lo pide. La
/// segunda: el mute manda sobre el solo, que es lo que un lector supone al
/// revés. Las dos están fijadas aquí.
final class AudibilityTests: XCTestCase {

    // MARK: - Sin solos

    /// El estado de partida: los doce suenan.
    func testWithNothingSetEveryTrackIsAudible() {
        let state = MuteState()

        for index in 0..<Pattern.trackCount {
            XCTAssertTrue(state.isAudible(index), "Track \(index)")
        }
    }

    /// Un mute calla a uno y deja a los otros once.
    func testOneMuteSilencesExactlyOneTrack() {
        let state = MuteState().togglingMute(4)

        XCTAssertFalse(state.isAudible(4))
        for index in 0..<Pattern.trackCount where index != 4 {
            XCTAssertTrue(state.isAudible(index), "Track \(index)")
        }
    }

    // MARK: - Con solos

    /// Un solo deja sonando a uno y calla a los once restantes, **sin que
    /// ninguno esté muteado**: es el solo lo que los excluye.
    func testOneSoloLeavesOnlyThatTrackAudible() {
        let state = MuteState().togglingSolo(7)

        XCTAssertTrue(state.isAudible(7))
        for index in 0..<Pattern.trackCount where index != 7 {
            XCTAssertFalse(state.isAudible(index), "Track \(index)")
            XCTAssertFalse(state.isMuted(index), "Track \(index) no está muteado")
        }
    }

    /// **El solo es aditivo:** dos soleados suenan los dos. Aislar bombo y caja
    /// juntos es la operación normal, y el solo exclusivo la prohibiría.
    func testTwoSolosLeaveBothAudible() {
        let state = MuteState().togglingSolo(0).togglingSolo(5)

        XCTAssertTrue(state.isAudible(0))
        XCTAssertTrue(state.isAudible(5))
        for index in 0..<Pattern.trackCount where index != 0 && index != 5 {
            XCTAssertFalse(state.isAudible(index), "Track \(index)")
        }
    }

    /// Soltar el último solo devuelve los doce. Sin esto, un solo suelto por
    /// error dejaría la app muda sin nada encendido que lo explique.
    func testReleasingTheLastSoloBringsEverybodyBack() {
        let state = MuteState().togglingSolo(3).togglingSolo(3)

        for index in 0..<Pattern.trackCount {
            XCTAssertTrue(state.isAudible(index), "Track \(index)")
        }
    }

    /// Soltar **uno** de dos solos deja al otro mandando.
    func testReleasingOneOfTwoSolosKeepsTheOtherInCharge() {
        let state = MuteState().togglingSolo(3).togglingSolo(8).togglingSolo(3)

        XCTAssertTrue(state.isAudible(8))
        XCTAssertFalse(state.isAudible(3))
    }

    // MARK: - Cuando los dos se cruzan

    /// **El mute manda sobre el solo.** Un Track soleado y muteado calla: es la
    /// regla que se lee del revés con facilidad, y la que evita el estado
    /// imposible de "está en solo, no suena, y no se ve por qué".
    func testAMutedTrackStaysSilentEvenWhenSoloed() {
        let state = MuteState().togglingSolo(2).togglingMute(2)

        XCTAssertTrue(state.isSoloed(2))
        XCTAssertTrue(state.isMuted(2))
        XCTAssertFalse(state.isAudible(2))
    }

    /// Y con otro Track soleado además, para que el solo tenga a quien dejar
    /// sonando: el muteado sigue callado y el otro suena.
    func testTheMuteOfASoloedTrackDoesNotSilenceTheOtherSoloedOne() {
        let state = MuteState()
            .togglingSolo(2).togglingMute(2)
            .togglingSolo(9)

        XCTAssertFalse(state.isAudible(2))
        XCTAssertTrue(state.isAudible(9))
    }

    /// Un mute sobre un Track que ya callaba por el solo de otro no se nota al
    /// oído, pero tiene que quedar registrado: al soltar el solo, ese sigue
    /// muteado.
    func testAMuteSetWhileSoloIsActiveSurvivesTheSoloRelease() {
        var state = MuteState().togglingSolo(1)
        state = state.togglingMute(6)
        XCTAssertFalse(state.isAudible(6))

        state = state.togglingSolo(1)

        XCTAssertFalse(state.isAudible(6), "el mute sigue puesto")
        XCTAssertTrue(state.isAudible(0))
    }

    // MARK: - Bordes

    /// Un índice que no es de ningún Track no es audible: no hay nada que oír.
    func testAnIndexOutsideTheTwelveIsNotAudible() {
        let state = MuteState()

        XCTAssertFalse(state.isAudible(-1))
        XCTAssertFalse(state.isAudible(Pattern.trackCount))
    }
}
