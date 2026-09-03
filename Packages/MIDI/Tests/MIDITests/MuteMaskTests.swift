import Engine
import XCTest
@testable import MIDI

/// Tests de `MuteMask`: doce mutes y doce solos en una sola palabra atómica.
///
/// **Lo que estas pruebas fijan no es la mecánica de bits, que es trivial, sino
/// la forma del tipo.** Los dos juegos se leen de un tirón porque el hilo del
/// scheduler decide con los dos a la vez: si se pudieran leer por separado,
/// existiría un instante en el que el mute es el de antes y el solo el de
/// después — y en ese instante, o calla todo, o no calla nada.
final class MuteMaskTests: XCTestCase {

    // MARK: - El estado leído

    /// Nace en silencio de mezcla: nada muteado, nada soleado.
    func testAFreshMaskHasNothingMutedAndNothingSoloed() {
        let state = MuteMask().load()

        for index in 0..<Pattern.trackCount {
            XCTAssertFalse(state.isMuted(index))
            XCTAssertFalse(state.isSoloed(index))
        }
        XCTAssertFalse(state.hasAnySolo)
    }

    /// Alternar el mute de un Track no toca a ninguno de los otros once.
    ///
    /// Se prueban el primero y el último porque son los extremos del campo de
    /// bits: un desplazamiento mal escrito los rompe antes que a los de en
    /// medio.
    func testTogglingOneMuteLeavesEveryOtherTrackAlone() {
        let mask = MuteMask()

        mask.toggleMute(0)
        mask.toggleMute(Pattern.trackCount - 1)

        let state = mask.load()
        for index in 0..<Pattern.trackCount {
            let expected = index == 0 || index == Pattern.trackCount - 1
            XCTAssertEqual(state.isMuted(index), expected, "Track \(index)")
            XCTAssertFalse(state.isSoloed(index), "Track \(index)")
        }
    }

    /// Y lo mismo por el lado del solo, que vive en la otra mitad de la palabra.
    func testTogglingOneSoloLeavesEveryOtherTrackAlone() {
        let mask = MuteMask()

        mask.toggleSolo(0)
        mask.toggleSolo(Pattern.trackCount - 1)

        let state = mask.load()
        for index in 0..<Pattern.trackCount {
            let expected = index == 0 || index == Pattern.trackCount - 1
            XCTAssertEqual(state.isSoloed(index), expected, "Track \(index)")
            XCTAssertFalse(state.isMuted(index), "Track \(index)")
        }
    }

    /// **Mute y solo del mismo Track son independientes.** Es lo que permite el
    /// estado que la spec exige resolver —soleado y muteado a la vez— y que un
    /// solo botón de tres posiciones no podría representar.
    func testMuteAndSoloOfTheSameTrackAreIndependent() {
        let mask = MuteMask()

        mask.toggleMute(3)
        mask.toggleSolo(3)

        let state = mask.load()
        XCTAssertTrue(state.isMuted(3))
        XCTAssertTrue(state.isSoloed(3))
    }

    /// Alternar dos veces devuelve al estado de partida: es un toggle, no un set.
    func testTogglingTwiceReturnsToTheStartingState() {
        let mask = MuteMask()

        mask.toggleMute(5)
        mask.toggleMute(5)
        mask.toggleSolo(5)
        mask.toggleSolo(5)

        XCTAssertEqual(mask.load(), MuteMask().load())
    }

    // MARK: - Los bordes

    /// **Un índice fuera de los doce no enciende nada y no revienta.** Llega de
    /// un step button, que es hardware: el mismo criterio que ya rige para un CC
    /// sin asignar — no publica y no es un error.
    func testAnIndexOutsideTheTwelveChangesNothing() {
        let mask = MuteMask()
        let before = mask.load()

        mask.toggleMute(Pattern.trackCount)
        mask.toggleMute(-1)
        mask.toggleMute(64)
        mask.toggleSolo(Pattern.trackCount)
        mask.toggleSolo(-1)
        mask.toggleSolo(64)

        XCTAssertEqual(mask.load(), before)
        XCTAssertFalse(mask.load().hasAnySolo)
    }

    /// `hasAnySolo` es la pregunta de la que depende la regla de audibilidad, y
    /// tiene que apagarse sola al soltar el último.
    func testHasAnySoloTracksTheWholeField() {
        let mask = MuteMask()
        XCTAssertFalse(mask.load().hasAnySolo)

        mask.toggleSolo(2)
        XCTAssertTrue(mask.load().hasAnySolo)

        mask.toggleSolo(7)
        XCTAssertTrue(mask.load().hasAnySolo)

        mask.toggleSolo(2)
        XCTAssertTrue(mask.load().hasAnySolo, "queda el del Track 7")

        mask.toggleSolo(7)
        XCTAssertFalse(mask.load().hasAnySolo)
    }

    /// **Mutear los doce no desborda a la mitad del solo.** Es el fallo que la
    /// disposición en una sola palabra hace posible, así que se fija: los doce
    /// mutes encendidos dejan el campo del solo intacto.
    func testFillingEveryMuteDoesNotLeakIntoTheSoloField() {
        let mask = MuteMask()

        for index in 0..<Pattern.trackCount { mask.toggleMute(index) }

        let state = mask.load()
        XCTAssertFalse(state.hasAnySolo)
        for index in 0..<Pattern.trackCount {
            XCTAssertTrue(state.isMuted(index), "Track \(index)")
            XCTAssertFalse(state.isSoloed(index), "Track \(index)")
        }
    }

    // MARK: - La forma del tipo

    /// **Una sola lectura devuelve los dos juegos.** No es una comprobación de
    /// valores: es la razón de ser del tipo. Un `MuteState` completo sale de un
    /// `load()`, así que no existe forma de leer el mute de un instante con el
    /// solo de otro.
    func testOneLoadCarriesBothFields() {
        let mask = MuteMask()
        mask.toggleMute(1)
        mask.toggleSolo(4)

        let state = mask.load()

        XCTAssertTrue(state.isMuted(1))
        XCTAssertTrue(state.isSoloed(4))
        XCTAssertFalse(state.isMuted(4))
        XCTAssertFalse(state.isSoloed(1))
    }

    /// El estado leído es un valor trivial: se copia al hilo del scheduler sin
    /// retener nada, por la misma razón que `Cycle` y `Pattern`.
    func testTheLoadedStateIsAPlainValue() {
        XCTAssertTrue(_isPOD(MuteState.self))
    }

    /// Escribir un estado entero es la vía que usará la pantalla, y tiene que
    /// dar exactamente lo que se le dio.
    func testStoringAStateReadsItBack() {
        let mask = MuteMask()
        var state = MuteState()
        state = state.togglingMute(0).togglingSolo(11)

        mask.store(state)

        XCTAssertEqual(mask.load(), state)
    }
}
