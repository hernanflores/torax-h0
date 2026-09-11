import Engine
import XCTest

@testable import MIDI

/// Tests del reanclaje de la rejilla — Fase 2 de `division-hot-grid_20260911`.
///
/// **El invariante de `LookAheadScheduler` es lo que está en juego.** Sobre
/// llamadas sucesivas, cada Step se emite exactamente una vez y los rangos nunca
/// retroceden: duplicar un Step es una nota repetida y omitirlo es una nota
/// perdida. Cambiar la rejilla a media reproducción es la primera cosa que puede
/// romperlo, así que aquí se prueba que no lo rompe (FR7).
///
/// **El ancla es el Step aún no entregado.** No el que suena ni el último
/// emitido: el siguiente. Es lo que hace que el reanclaje no pueda producir un
/// offset anterior al horizonte ya servido — ese Step todavía no cabía en
/// ninguna ventana, así que su instante está por delante.
final class LookAheadRebaseTests: XCTestCase {

    /// 120 BPM, 1/16 → un Step cada 125 ms.
    private func makeScheduler(startingAtStep step: Int = 0) -> LookAheadScheduler {
        LookAheadScheduler(
            timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth),
            startingAtStep: step
        )
    }

    private let stepNanoseconds: Int64 = 125_000_000

    // MARK: - La marca de agua no se mueve (FR5)

    /// Reanclar cambia lo que **duran** los Steps, no por cuál se va.
    func testRebasingDoesNotMoveTheWatermark() {
        var scheduler = makeScheduler()
        XCTAssertEqual(scheduler.advance(toHorizon: 4 * stepNanoseconds), 0..<4)

        scheduler.rebase(to: .eighth)

        XCTAssertEqual(scheduler.nextStep, 4)
    }

    // MARK: - El instante del corte se conserva (FR6)

    /// El Step aún no entregado cae donde ya iba a caer, y de ahí en adelante
    /// mandan los 250 ms de la corchea.
    func testTheNextStepKeepsItsInstantAndTheRestFollowTheNewDivision() {
        var scheduler = makeScheduler()
        _ = scheduler.advance(toHorizon: 4 * stepNanoseconds)
        let instantOfStepFour = 4 * stepNanoseconds

        scheduler.rebase(to: .eighth)

        XCTAssertEqual(scheduler.timeline.nanosecondOffset(forStep: 4), instantOfStepFour)
        XCTAssertEqual(
            scheduler.timeline.nanosecondOffset(forStep: 5), instantOfStepFour + 250_000_000)
    }

    // MARK: - El invariante (FR7, criterio 3)

    /// **Ningún Step se pierde ni se repite** al reanclar entre dos ventanas.
    /// Se recorren ventanas sucesivas con un cambio de Division en medio y se
    /// comprueba que la secuencia de índices emitidos es exactamente
    /// `0, 1, 2, …`, sin huecos y sin repeticiones.
    func testNoStepIsLostOrRepeatedAcrossARebase() {
        var scheduler = makeScheduler()
        var emitted: [Int] = []
        var horizon: Int64 = 0

        for window in 0..<40 {
            horizon += 20_000_000  // Ventanas de 20 ms, como las del scheduler.
            emitted.append(contentsOf: scheduler.advance(toHorizon: horizon))

            // Dos cambios de Division a media reproducción, en ventanas
            // cualesquiera: uno a más lento y otro a más rápido.
            if window == 7 { scheduler.rebase(to: .eighth) }
            if window == 21 { scheduler.rebase(to: .thirtySecond) }
        }

        XCTAssertFalse(emitted.isEmpty)
        XCTAssertEqual(emitted, Array(emitted.first!...emitted.last!))
    }

    /// **Ningún Step posterior al reanclaje cae antes del horizonte ya
    /// entregado.** Si lo hiciera, se pediría a CoreMIDI un evento para un
    /// instante que ya pasó, que es la forma que tendría este cambio de sonar
    /// como un tropiezo.
    func testNoStepAfterARebaseFallsBeforeTheDeliveredHorizon() {
        var scheduler = makeScheduler()
        let horizon: Int64 = 4 * stepNanoseconds
        _ = scheduler.advance(toHorizon: horizon)

        for division in [Division.whole, .half, .quarter, .eighth, .sixteenth, .thirtySecond] {
            var rebased = scheduler
            rebased.rebase(to: division)

            XCTAssertGreaterThanOrEqual(
                rebased.timeline.nanosecondOffset(forStep: rebased.nextStep), horizon,
                "Con \(division) el Step siguiente caería antes del horizonte ya servido")
        }
    }

    // MARK: - El caso de casi todas las ventanas

    /// Reanclar sobre la **misma** Division no cambia nada de nada. Es lo que
    /// permite al hilo del scheduler no tener que acordarse de si ya reancló.
    func testRebasingToTheSameDivisionChangesNothing() {
        var scheduler = makeScheduler()
        var untouched = makeScheduler()

        _ = scheduler.advance(toHorizon: 4 * stepNanoseconds)
        _ = untouched.advance(toHorizon: 4 * stepNanoseconds)

        scheduler.rebase(to: .sixteenth)

        XCTAssertEqual(
            scheduler.advance(toHorizon: 10 * stepNanoseconds),
            untouched.advance(toHorizon: 10 * stepNanoseconds))
    }

    // MARK: - El efecto que se busca

    /// Con la rejilla el doble de lenta, el mismo horizonte trae la mitad de
    /// Steps. Es el cambio de velocidad de la línea, visto desde la ventana.
    func testASlowerGridYieldsFewerStepsForTheSameHorizon() {
        var scheduler = makeScheduler()
        _ = scheduler.advance(toHorizon: 4 * stepNanoseconds)

        scheduler.rebase(to: .eighth)

        // Cuatro Steps de 1/16 más ocho de 1/16 por delante: con la corchea, en
        // ese hueco caben cuatro y no ocho.
        XCTAssertEqual(scheduler.advance(toHorizon: 12 * stepNanoseconds), 4..<8)
    }
}
