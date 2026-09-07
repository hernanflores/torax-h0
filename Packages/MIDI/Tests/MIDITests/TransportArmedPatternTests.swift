import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de cómo el transporte arma y adopta un Pattern.
///
/// **Quién decide qué camino se usa es el transporte, no la pantalla.** Con el
/// transporte corriendo, elegir un Pattern arma y espera al compás (FR6); parado,
/// publica y ya (FR5). Que la decisión viva aquí es lo que evita que cada sitio
/// de la interfaz tenga que acordarse de la regla.
final class TransportArmedPatternTests: XCTestCase {

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

    private func pattern(steps: Int) -> Pattern {
        Pattern().replacing(
            Cycle(shape: Shape(steps: Steps(steps)!, pulses: Pulses(1)!)),
            at: 0
        )
    }

    private func steps(of pattern: Pattern) -> Int? {
        pattern.cycle(at: 0)?.shape.steps.count
    }

    // MARK: - Parado, inmediato (FR5)

    /// **Con el transporte parado no hay rejilla que respetar**: el Pattern
    /// elegido pasa a ser el vigente y el próximo Play arranca con él.
    func testSelectingAPatternWhileStoppedIsImmediate() {
        let transport = makeTransport(pattern(steps: 16))

        transport.select(pattern(steps: 8))

        XCTAssertEqual(steps(of: transport.pattern), 8)
        XCTAssertFalse(transport.hasArmedPattern)
    }

    // MARK: - Stop se lleva lo pendiente (FR10)

    /// **Stop con un pendiente lo deja vigente.**
    ///
    /// Parado no hay rejilla y el usuario ya dijo qué quiere: dejarlo esperando
    /// significaría que pulsar Pattern y luego Stop no hace nada, que son dos
    /// gestos deliberados anulándose.
    func testStopAdoptsThePendingPattern() {
        let transport = makeTransport(pattern(steps: 16))
        transport.armForNextBar(pattern(steps: 8))

        transport.stop()

        XCTAssertEqual(steps(of: transport.pattern), 8)
    }

    /// Y no queda nada armado detrás: no hay estado pendiente que persistir
    /// entre sesiones.
    func testAfterStopNothingIsArmed() {
        let transport = makeTransport(pattern(steps: 16))
        transport.armForNextBar(pattern(steps: 8))

        transport.stop()

        XCTAssertFalse(transport.hasArmedPattern)
    }

    /// Stop sin nada pendiente no cambia el Pattern vigente.
    func testStopWithNothingArmedChangesNothing() {
        let transport = makeTransport(pattern(steps: 16))

        transport.stop()

        XCTAssertEqual(steps(of: transport.pattern), 16)
    }

    /// Armar dos veces antes de parar deja el último, como en el handoff.
    func testStopAdoptsTheLastArmedPattern() {
        let transport = makeTransport(pattern(steps: 16))
        transport.armForNextBar(pattern(steps: 8))
        transport.armForNextBar(pattern(steps: 12))

        transport.stop()

        XCTAssertEqual(steps(of: transport.pattern), 12)
    }

    // MARK: - Armar no cambia lo que suena

    func testArmingDoesNotChangeTheCurrentPattern() {
        let transport = makeTransport(pattern(steps: 16))

        transport.armForNextBar(pattern(steps: 8))

        XCTAssertEqual(steps(of: transport.pattern), 16)
        XCTAssertTrue(transport.hasArmedPattern)
    }

    /// **Elegir un Pattern hace lo que toca según el transporte**, y quien llama
    /// no tiene que saber la regla.
    func testSelectingDecidesTheRouteByItself() {
        let transport = makeTransport(pattern(steps: 16))

        transport.select(pattern(steps: 8))
        XCTAssertEqual(steps(of: transport.pattern), 8, "parado tenía que ser inmediato")
        XCTAssertFalse(transport.hasArmedPattern)
    }
}
