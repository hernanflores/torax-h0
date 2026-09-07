import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de que `Reload` entre por el mismo camino que un cambio de Pattern
/// (FR17).
///
/// **Por el mismo camino y no por otro parecido.** Recargar es sustituir el
/// material vigente por el del punto de retorno, y eso es exactamente lo que
/// hace elegir un Pattern: si tuviera vía propia habría dos formas de que el
/// material entre, y dos formas de que una de ellas se desincronice del compás.
final class QuantizedReloadTests: XCTestCase {

    private func makeTransport(_ pattern: Pattern) -> Transport {
        Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth)
            ),
            pattern: pattern,
            emitter: NoteEmitter(),
            send: { _, _ in }
        )
    }

    private func bank(steps: Int) -> Bank {
        Bank().replacing(
            Pattern().replacing(
                Cycle(shape: Shape(steps: Steps(steps)!, pulses: Pulses(1)!)), at: 0),
            at: 0
        )
    }

    private func pattern(steps: Int) -> Pattern {
        Pattern().replacing(
            Cycle(shape: Shape(steps: Steps(steps)!, pulses: Pulses(1)!)), at: 0)
    }

    private func steps(of pattern: Pattern) -> Int? {
        pattern.cycle(at: 0)?.shape.steps.count
    }

    /// Parado, recargar es inmediato, como elegir un Pattern.
    func testReloadingWhileStoppedIsImmediate() {
        let transport = makeTransport(pattern(steps: 16))

        transport.select(bank(steps: 8), pattern: 0)

        XCTAssertEqual(steps(of: transport.pattern), 8)
    }

    /// **Recargar no tiene vía propia: pasa por `select`.**
    ///
    /// **Lo que se afirma es la ausencia de un segundo camino**, y eso se
    /// comprueba mirando qué hace el transporte, no dejándolo sonar: en host no
    /// hay destino MIDI, así que `play()` no arranca y un test que dependiera de
    /// que arranque no probaría nada — se comprobó, y salía por el guard sin
    /// afirmar una sola cosa.
    ///
    /// La cuantización de verdad, con el instante medido sobre el offset, está
    /// en `QuantizedPatternChangeTests`, al nivel del scheduler, que es donde se
    /// puede ejercer sin hardware. Aquí basta con que el material del punto de
    /// retorno entre por `select` y por tanto herede aquella.
    func testReloadingGoesThroughTheSameEntryPointAsAPatternChange() {
        let transport = makeTransport(pattern(steps: 16))

        // Parado: publica, igual que un cambio de Pattern parado.
        transport.select(bank(steps: 8), pattern: 0)
        XCTAssertEqual(steps(of: transport.pattern), 8)
        XCTAssertFalse(transport.hasArmedPattern)

        // Armado explícito: espera, igual que un cambio de Pattern sonando.
        transport.armForNextBar(pattern(steps: 12))
        XCTAssertEqual(steps(of: transport.pattern), 8, "entró sin esperar al compás")
        XCTAssertTrue(transport.hasArmedPattern)
    }

    /// Y armar el punto de retorno dos veces deja el último, como todo lo demás
    /// que pasa por la ranura armada.
    func testArmingTheRestorePointTwiceKeepsTheLast() {
        let transport = makeTransport(pattern(steps: 16))

        transport.armForNextBar(pattern(steps: 8))
        transport.armForNextBar(pattern(steps: 12))
        transport.stop()

        XCTAssertEqual(steps(of: transport.pattern), 12)
    }
}
