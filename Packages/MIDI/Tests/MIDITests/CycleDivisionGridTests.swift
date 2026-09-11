import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests del cambio de rejilla en el límite de vuelta — Fase 3 de
/// `division-hot-grid_20260911`.
///
/// **La otra puerta del mismo defecto.** Cada Cycle tiene su propio Shape y por
/// tanto su propia Division, pero la rejilla de un Track se fijaba en Play con la
/// del Cycle 1: un Cycle 2 en 1/8 sonaba sobre la rejilla del 1/16. El knob
/// entra por `refresh(with: Track)` al principio de la ventana; el avance de
/// Cycle ocurre **dentro** del bucle de Steps de una ventana ya calculada con la
/// rejilla vieja, y por eso es el único caso de este track que puede perder o
/// duplicar una nota.
///
/// Se testea sobre `PatternScheduler` porque es donde el avance de Cycle y el
/// relevo del snapshot conviven, y el horizonte se da a mano: «el cambio cae a
/// mitad de ventana» es un hecho que se elige, no una carrera contra el reloj.
final class CycleDivisionGridTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// A 120 BPM: un Step de 1/16 dura 125 ms, uno de 1/8 250 ms y uno de 1/32
    /// 62,5 ms.
    private let sixteenth: Int64 = 125_000_000
    private let eighth: Int64 = 250_000_000
    private let thirtySecond: Int64 = 62_500_000

    /// Un Cycle de 16 Steps que dispara en todos, reconocible por su altura.
    private func cycle(pitch: Int, division: Division) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!, division: division),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    /// Un Track con dos Cycles activos: el 1 en 1/16 con altura 48 y el 2 en la
    /// Division pedida con altura 72.
    private func scheduler(secondCycleIn division: Division) -> PatternScheduler {
        let track =
            Track(cycle(pitch: 48, division: .sixteenth))
            .withActiveCount(2)
            .replacing(cycle(pitch: 72, division: division), at: 1)
        return PatternScheduler(tempo: tempo, pattern: Pattern().replacing(track, at: 0))
    }

    private typealias Event = (step: Int, pitch: Int?, offset: Int64)

    /// Lo emitido por el Track 0 hasta el horizonte, en una sola llamada.
    private func emit(_ scheduler: PatternScheduler, toHorizon horizon: Int64) -> [Event] {
        var events: [Event] = []
        scheduler.advance(toHorizon: horizon, refreshingFrom: nil) {
            track, _, step, pitch, _, offset in
            guard track == 0 else { return }
            events.append((step, pitch?.value, offset))
        }
        return events
    }

    /// Lo emitido por el Track 0 en ventanas de `window` nanosegundos hasta
    /// `end`, junto con el horizonte ya entregado cuando salió cada evento.
    private func emitInWindows(
        _ scheduler: PatternScheduler, of window: Int64, until end: Int64
    ) -> [(event: Event, deliveredBefore: Int64, horizon: Int64)] {
        var events: [(event: Event, deliveredBefore: Int64, horizon: Int64)] = []
        var delivered: Int64 = 0
        while delivered < end {
            let horizon = delivered + window
            scheduler.advance(toHorizon: horizon, refreshingFrom: nil) {
                track, _, step, pitch, _, offset in
                guard track == 0 else { return }
                events.append(((step, pitch?.value, offset), delivered, horizon))
            }
            delivered = horizon
        }
        return events
    }

    /// Dónde tiene que caer cada Step con el Cycle 1 en 1/16 y el Cycle 2 en
    /// 1/8: la primera vuelta mide 2 s, la segunda 4 s, y la tercera vuelve a
    /// 1/16 desde los 6 s.
    private func expectedOffsetSixteenthThenEighth(forStep step: Int) -> Int64 {
        switch step {
        case ..<16: Int64(step) * sixteenth
        case ..<32: 16 * sixteenth + Int64(step - 16) * eighth
        default: 16 * sixteenth + 16 * eighth + Int64(step - 32) * sixteenth
        }
    }

    // MARK: - La rejilla cambia con el Cycle (FR3, criterio 5)

    /// **Cycle 1 en 1/16 y Cycle 2 en 1/8: el espaciado se dobla al entrar el
    /// Cycle 2**, en el límite de vuelta. Es el criterio 5 del track, y lo que
    /// hoy no ocurre: el Cycle 2 suena con sus alturas sobre la rejilla del 1.
    func testTheSpacingChangesWhenTheSecondCycleEnters() {
        let events = emit(scheduler(secondCycleIn: .eighth), toHorizon: 7_000_000_000)

        XCTAssertEqual(events.map(\.step), Array(0..<40))
        for event in events {
            XCTAssertEqual(
                event.offset, expectedOffsetSixteenthThenEighth(forStep: event.step),
                "Step \(event.step)")
        }
    }

    /// **El primer Step de la vuelta nueva ya suena con la rejilla nueva**, como
    /// ya suena con el material nuevo (FR5 de la rebanada de Cycles). Cae donde
    /// la vuelta anterior lo dejaba —2 s— y el siguiente, 250 ms después.
    func testTheFirstStepOfTheNewTurnAlreadySoundsOnTheNewGrid() {
        let events = emit(scheduler(secondCycleIn: .eighth), toHorizon: 3_000_000_000)

        let opening = events.first(where: { $0.step == 16 })
        let second = events.first(where: { $0.step == 17 })
        XCTAssertEqual(opening?.pitch, 72)
        XCTAssertEqual(opening?.offset, 2_000_000_000)
        XCTAssertEqual(second?.pitch, 72)
        XCTAssertEqual(second?.offset, 2_000_000_000 + eighth, "el Step 17 siguió en 1/16")
    }

    // MARK: - A mitad de ventana (FR7)

    /// **El cambio a mitad de ventana, hacia más lento.** Con ventanas de 30 ms
    /// el cierre de vuelta —2 s— cae dentro de una, no en su borde. Ningún Step
    /// se pierde ni se repite, y lo emitido es exactamente lo que da pedirlo de
    /// una vez: la ventana no puede decidir dónde cae un Step.
    func testNoStepIsLostOrRepeatedWhenTheChangeFallsMidWindowTowardsSlower() {
        let chopped = emitInWindows(
            scheduler(secondCycleIn: .eighth), of: 30_000_000, until: 7_000_000_000)
        let whole = emit(scheduler(secondCycleIn: .eighth), toHorizon: chopped.last!.horizon)

        let steps = chopped.map(\.event.step)
        XCTAssertEqual(steps, Array(steps.first!...steps.last!), "un Step perdido o repetido")
        XCTAssertEqual(chopped.map(\.event.offset), whole.map(\.offset))
    }

    /// **Y hacia más rápido, que es el caso que obliga a reentrar.** Con el
    /// Cycle 2 en 1/32, tras el cierre de vuelta caben en la ventana más Steps
    /// de los que la rejilla vieja había calculado. Si no se emitieran en ella,
    /// saldrían en la siguiente con un instante que ya quedó atrás.
    func testNoStepIsDeliveredLateWhenTheChangeFallsMidWindowTowardsFaster() {
        let chopped = emitInWindows(
            scheduler(secondCycleIn: .thirtySecond), of: 30_000_000, until: 4_000_000_000)

        for (event, deliveredBefore, horizon) in chopped {
            XCTAssertGreaterThanOrEqual(
                event.offset, deliveredBefore,
                "el Step \(event.step) salió para un instante ya entregado")
            XCTAssertLessThan(
                event.offset, horizon, "el Step \(event.step) salió antes de su ventana")
        }

        let steps = chopped.map(\.event.step)
        XCTAssertEqual(steps, Array(steps.first!...steps.last!), "un Step perdido o repetido")

        let opening = chopped.first(where: { $0.event.step == 16 })?.event.offset
        let second = chopped.first(where: { $0.event.step == 17 })?.event.offset
        XCTAssertEqual(opening, 2_000_000_000)
        XCTAssertEqual(second, 2_000_000_000 + thirtySecond, "el Step 17 siguió en 1/16")
    }

    // MARK: - La vuelta atrás (FR6)

    /// **Volver al Cycle 1 devuelve la rejilla, anclada al cierre de vuelta.**
    /// La segunda vuelta acaba a los 6 s —2 s de 1/16 más 4 s de 1/8—, así que
    /// el Step 32 cae ahí y no a los 4 s, que es donde lo pondría una rejilla
    /// de 1/16 medida desde Play.
    func testReturningToTheFirstCycleAnchorsAtTheTurnCloseAndNotAtPlay() {
        let events = emit(scheduler(secondCycleIn: .eighth), toHorizon: 7_000_000_000)

        let back = events.first(where: { $0.step == 32 })
        let next = events.first(where: { $0.step == 33 })
        XCTAssertEqual(back?.pitch, 48)
        XCTAssertEqual(back?.offset, 6_000_000_000)
        XCTAssertEqual(next?.offset, 6_000_000_000 + sixteenth)
    }
}
