import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests del estado de un hueco de Pattern.
///
/// **Bajó de la vista el 2026-09-07.** `PatternGrid.state(_:)` lo calculaba en
/// `App`, con un comentario que decía que se quedaba arriba «porque la premisa
/// de la cáscara —que solo existe el índice 0— es una limitación temporal de
/// esta pantalla, no una propiedad del dominio». Esa premisa ya no existe: los
/// 256 Patterns existen, así que el estado pasa a ser una lectura directa y baja
/// a donde hay tests.
///
/// **El cuarto estado es `queued`**, y es lo que la rebanada añade: entre pulsar
/// un Pattern y el compás en que entra pasa hasta un compás, y sin decirlo la
/// espera se lee como que el botón no funciona.
final class PatternSlotStateTests: XCTestCase {

    /// Un hueco sin material está vacío, suene lo que suene.
    func testAnEmptySlotIsEmpty() {
        XCTAssertEqual(
            PatternSlotState(
                hasMaterial: false, isPlaying: false, isQueued: false, isRunning: false),
            .empty)
        XCTAssertEqual(
            PatternSlotState(hasMaterial: false, isPlaying: true, isQueued: true, isRunning: true),
            .empty)
    }

    /// Con material y sin transporte, está listo.
    func testMaterialWithoutTransportIsReady() {
        XCTAssertEqual(
            PatternSlotState(hasMaterial: true, isPlaying: true, isQueued: false, isRunning: false),
            .ready)
    }

    /// Con material, sonando y con el transporte corriendo, suena.
    func testTheSoundingSlotIsPlaying() {
        XCTAssertEqual(
            PatternSlotState(hasMaterial: true, isPlaying: true, isQueued: false, isRunning: true),
            .playing)
    }

    /// **El que espera al compás está `queued`.**
    func testTheArmedSlotIsQueued() {
        XCTAssertEqual(
            PatternSlotState(hasMaterial: true, isPlaying: false, isQueued: true, isRunning: true),
            .queued)
    }

    /// **El que suena manda sobre el que espera.**
    ///
    /// Coinciden cuando alguien vuelve a pulsar el Pattern que ya está sonando:
    /// no es una espera, es no cambiar de sitio. Decir `queued` ahí prometería un
    /// cambio que no va a ocurrir.
    func testPlayingWinsOverQueued() {
        XCTAssertEqual(
            PatternSlotState(hasMaterial: true, isPlaying: true, isQueued: true, isRunning: true),
            .playing)
    }

    /// Un hueco armado con el transporte parado no espera a nada: parado el
    /// cambio es inmediato (FR5), así que `queued` no puede darse.
    func testThereIsNoQueuedStateWhileStopped() {
        XCTAssertEqual(
            PatternSlotState(hasMaterial: true, isPlaying: false, isQueued: true, isRunning: false),
            .ready)
    }

    /// Los cuatro tienen etiqueta, y las cuatro son distintas: es lo que impide
    /// que un refactor deje dos estados diciendo lo mismo.
    func testTheFourStatesReadDifferently() {
        let labels = PatternSlotState.allCases.map(\.label)
        XCTAssertEqual(labels.count, 4)
        XCTAssertEqual(Set(labels).count, 4)
        XCTAssertEqual(PatternSlotState.empty.label, "empty")
        XCTAssertEqual(PatternSlotState.ready.label, "ready")
        XCTAssertEqual(PatternSlotState.playing.label, "playing")
        XCTAssertEqual(PatternSlotState.queued.label, "queued")
    }

    /// **La rejilla entera de un Bank de una vez**, que es como la pantalla lo
    /// necesita: dieciséis estados, no dieciséis preguntas.
    func testABankReportsTheStateOfItsSixteenSlots() {
        let bank = Bank().replacing(Pattern.initial, at: 0).replacing(Pattern.initial, at: 5)

        let states = bank.slotStates(playing: 0, queued: 5, isRunning: true)

        XCTAssertEqual(states.count, Bank.patternCount)
        XCTAssertEqual(states[0], .playing)
        XCTAssertEqual(states[5], .queued)
        XCTAssertEqual(states[1], .empty)
    }

    /// Sin nada armado, ninguno espera.
    func testWithNothingQueuedNoSlotWaits() {
        let bank = Bank().replacing(Pattern.initial, at: 0)

        let states = bank.slotStates(playing: 0, queued: nil, isRunning: true)

        XCTAssertEqual(states[0], .playing)
        XCTAssertFalse(states.contains(.queued))
    }
}
