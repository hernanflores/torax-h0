import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de cambiar de Bank (FR11, FR12).
///
/// **Cambiar de Bank es cambiar de Pattern más el tempo.** Una sola regla de
/// cuantización en el producto: el material entra en el compás, y el tempo entra
/// con él en vez de saltar a media frase.
///
/// **Con reloj externo el tempo del Bank no manda** (FR12). El maestro lo pone y
/// el dato guardado sobrevive: vuelve a mandar en cuanto la fuente sea
/// `Internal`. Sin esto, esta rebanada contradiría a `external-clock_20260903`.
final class BankChangeTests: XCTestCase {

    private func makeTransport(_ pattern: Pattern = Pattern.initial) -> Transport {
        Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
            ),
            pattern: pattern,
            emitter: NoteEmitter(),
            send: { _, _ in }
        )
    }

    private func bank(_ tempo: Double, steps: Int) -> Bank {
        Bank()
            .replacing(
                Pattern().replacing(
                    Cycle(shape: Shape(steps: Steps(steps)!, pulses: Pulses(1)!)), at: 0),
                at: 0
            )
            .withTempo(Tempo(beatsPerMinute: tempo)!)
    }

    private func steps(of pattern: Pattern) -> Int? {
        pattern.cycle(at: 0)?.shape.steps.count
    }

    // MARK: - Parado

    /// Parado, el Bank entra entero e inmediato: material y tempo.
    func testChangingBankWhileStoppedIsImmediate() {
        let transport = makeTransport()

        transport.select(bank(96, steps: 8), pattern: 0)

        XCTAssertEqual(steps(of: transport.pattern), 8)
        XCTAssertEqual(transport.currentTempo, Tempo(beatsPerMinute: 96)!)
    }

    /// Entra **el Pattern seleccionado del Bank destino**, no siempre el primero.
    func testTheSelectedPatternOfTheTargetBankIsTheOneThatEnters() {
        let transport = makeTransport()
        let target = bank(120, steps: 8)
            .replacing(
                Pattern().replacing(
                    Cycle(shape: Shape(steps: Steps(12)!, pulses: Pulses(1)!)), at: 0),
                at: 5
            )

        transport.select(target, pattern: 5)

        XCTAssertEqual(steps(of: transport.pattern), 12)
    }

    /// Un índice fuera de rango no revienta ni cambia nada.
    func testAnOutOfRangePatternIndexChangesNothing() {
        let transport = makeTransport(
            Pattern().replacing(
                Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(1)!)), at: 0))

        transport.select(bank(96, steps: 8), pattern: 99)

        XCTAssertEqual(steps(of: transport.pattern), 16)
        XCTAssertEqual(transport.currentTempo, Tempo(beatsPerMinute: 120)!)
    }

    // MARK: - El tempo y el reloj

    /// **Con reloj interno, el Bank manda el tempo.**
    func testWithTheInternalClockTheBankSetsTheTempo() {
        let transport = makeTransport()
        transport.clockSource = .internal

        transport.select(bank(174, steps: 8), pattern: 0)

        XCTAssertEqual(transport.currentTempo, Tempo(beatsPerMinute: 174)!)
    }

    /// **Con reloj externo, no.** El tempo lo pone el maestro y cambiar de Bank
    /// no lo toca.
    func testWithTheExternalClockTheBankTempoIsIgnored() {
        let transport = makeTransport()
        transport.clockSource = .external

        transport.select(bank(174, steps: 8), pattern: 0)

        XCTAssertEqual(transport.currentTempo, Tempo(beatsPerMinute: 120)!)
    }

    /// **Y el material sí entra igual**: lo que el reloj externo decide es el
    /// tempo, no si se puede cambiar de Bank.
    func testTheMaterialStillEntersWithTheExternalClock() {
        let transport = makeTransport()
        transport.clockSource = .external

        transport.select(bank(174, steps: 8), pattern: 0)

        XCTAssertEqual(steps(of: transport.pattern), 8)
    }

    /// **El tempo guardado sobrevive.** Vuelve a mandar en cuanto la fuente sea
    /// `Internal`: el dato no se pierde, solo no se aplica.
    func testTheBankTempoComesBackWhenTheClockGoesInternal() {
        let transport = makeTransport()
        transport.clockSource = .external
        let target = bank(174, steps: 8)

        transport.select(target, pattern: 0)
        XCTAssertEqual(transport.currentTempo, Tempo(beatsPerMinute: 120)!)

        transport.clockSource = .internal
        transport.select(target, pattern: 0)

        XCTAssertEqual(transport.currentTempo, Tempo(beatsPerMinute: 174)!)
    }
}
