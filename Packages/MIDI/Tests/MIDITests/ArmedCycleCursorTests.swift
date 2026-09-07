import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de por qué Cycle empieza un Pattern que entra (FR8).
///
/// **El Pattern entra por el principio de su desarrollo**, como si le acabaran
/// de pulsar Play. Es lo que hace que disparar el break suene igual las dos
/// veces, que es lo que se espera de un botón en directo.
///
/// **Y es la otra mitad de por qué el cursor de reproducción no se guarda**: es
/// estado de ejecución, lo mueve este hilo, y persistirlo habría hecho que un
/// Pattern sonara distinto según cuándo se cerró la app.
final class ArmedCycleCursorTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// Un Track con **tres** Cycles activos, cada uno con una altura distinta, de
    /// modo que cada evento diga por qué Cycle va.
    ///
    /// **Tres y no cuatro, y el número importa.** El Track da cuatro vueltas por
    /// compás —cuatro Steps de 1/16—, así que con cuatro Cycles el cursor
    /// volvería al primero justo en el límite **por sí solo**, y el test pasaría
    /// sin que nadie lo hubiera reiniciado. Con tres, al llegar al compás el
    /// cursor está en el segundo: si el Pattern entrante no reinicia, se ve.
    private func developing(base: Int) -> Pattern {
        var track = Track(
            Cycle(
                shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!),
                pool: PitchPool().inserting(Pitch(base)!)
            )
        ).withActiveCount(3)

        for index in 1..<3 {
            track = track.replacing(
                Cycle(
                    shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!),
                    pool: PitchPool().inserting(Pitch(base + index)!)
                ),
                at: index
            )
        }
        return Pattern().replacing(track, at: 0)
    }

    private func events(
        upTo horizon: Int64, from scheduler: PatternScheduler, handoff: PatternHandoff
    ) -> [(offset: Int64, pitch: Int)] {
        var collected: [(offset: Int64, pitch: Int)] = []
        scheduler.advance(toHorizon: horizon, refreshingFrom: handoff) {
            _, _, _, pitch, _, offset in
            if let pitch { collected.append((offset, pitch.value)) }
        }
        return collected
    }

    /// **El Pattern que entra empieza por su primer Cycle activo.**
    ///
    /// El de antes lleva varias vueltas y su cursor está donde esté; el nuevo no
    /// hereda eso ni continúa donde lo dejó la última vez que sonó.
    func testTheIncomingPatternStartsOnItsFirstCycle() {
        let handoff = PatternHandoff(developing(base: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: developing(base: 60))

        // Un compás entero: cuatro Steps de 1/16 por vuelta, así que el Track da
        // cuatro vueltas y el cursor de Cycle se mueve varias veces.
        handoff.arm(developing(base: 72))
        let emitted = events(upTo: 4_000_000_000, from: scheduler, handoff: handoff)

        let afterChange = emitted.filter { $0.offset >= 2_000_000_000 }
        XCTAssertEqual(afterChange.first?.pitch, 72, "no entró por su primer Cycle")
    }

    /// Y sigue desarrollando desde ahí: 72, 73, 74, 75 en vueltas sucesivas.
    func testTheIncomingPatternKeepsDevelopingFromTheStart() {
        let handoff = PatternHandoff(developing(base: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: developing(base: 60))

        handoff.arm(developing(base: 72))
        let emitted = events(upTo: 4_000_000_000, from: scheduler, handoff: handoff)

        let afterChange = emitted.filter { $0.offset >= 2_000_000_000 }
        let byTurn = stride(from: 0, to: afterChange.count, by: 4).map { afterChange[$0].pitch }

        XCTAssertEqual(Array(byTurn.prefix(4)), [72, 73, 74, 72])
    }

    /// **El cursor de edición viaja con el Pattern y no se toca.** Es de
    /// pantalla, no de sonido: volver a un Pattern y encontrarlo editando otro
    /// Cycle sería perder el sitio.
    func testTheEditingCursorTravelsWithThePattern() {
        let incoming = developing(base: 72)
        let edited = incoming.replacing(
            incoming.track(at: 0)!.withEditing(2), at: 0)

        let handoff = PatternHandoff(developing(base: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: developing(base: 60))

        handoff.arm(edited)
        _ = events(upTo: 4_000_000_000, from: scheduler, handoff: handoff)

        XCTAssertEqual(scheduler.pattern.track(at: 0)?.editing, 2)
    }

    /// Publicar con el transporte parado **no** reinicia los cursores: es el
    /// camino de siempre, y reiniciarlo devolvería el desarrollo al principio en
    /// cada giro de knob — lo que `TrackScheduler.refresh(with:)` ya documenta.
    func testPublishingDoesNotRestartTheCycles() {
        let handoff = PatternHandoff(developing(base: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: developing(base: 60))

        // Dos vueltas: el cursor se mueve.
        _ = events(upTo: 500_000_000, from: scheduler, handoff: handoff)
        handoff.publish(developing(base: 60))
        let emitted = events(upTo: 750_000_000, from: scheduler, handoff: handoff)

        XCTAssertNotEqual(emitted.first?.pitch, 60, "publicar devolvió el desarrollo al Cycle 1")
    }
}
