import Engine
import XCTest

@testable import MIDI

/// Tests del gate contra la rejilla tras un cambio de Division — Fase 4 de
/// `division-hot-grid_20260911`, FR16.
///
/// **Las dos mitades del mismo valor vivían en sitios distintos.** El gate lo
/// recalcula `Transport` por nota con la Division del Cycle que emite; el
/// espaciado lo decidía una rejilla congelada en Play. Por eso girar el knob
/// cambiaba la duración de la nota y no la velocidad de la línea, que fue el
/// defecto reportado. Aquí se fija que, tras el cambio, **las dos salen del
/// mismo Step**.
///
/// **La duración de Step del gate se calcula como la calcula `Transport`**:
/// `MusicalTimeline(tempo:division: source.shape.division)`, en
/// `Transport.swift`, en el cierre que entrega cada Pulse al `NoteEmitter`. Sin
/// maestro externo la conversión a tiempo de reloj es la identidad, así que ese
/// valor llega tal cual. Se reproduce la expresión en vez de arrancar el
/// transporte porque cada arranque del hilo del scheduler es presión añadida
/// sobre el flake de CoreMIDI (`workflow.md`), y aquí no aportaría nada.
///
/// Los tempos elegidos dan duraciones de Step enteras en nanosegundos. Con una
/// no entera, la rejilla redondea desde el ancla y el gate trunca, y pueden
/// discrepar en un nanosegundo: es inaudible y no es de este track.
final class SustainGateDivisionTests: XCTestCase {

    private func cycle(division: Division, sustain: Int) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!, division: division),
            pool: PitchPool().inserting(Pitch(48)!),
            groove: Groove(
                velocity: .default, sustain: Sustain(percent: sustain)!,
                probability: .default)
        )
    }

    private struct Note {
        let step: Int
        let onNanoseconds: Int64
        let gateNanoseconds: Int64
        var offNanoseconds: Int64 { onNanoseconds + gateNanoseconds }
    }

    /// Una ventana en `from`, y tras publicar `to`, lo que sale hasta `horizon`,
    /// con el gate que le daría `Transport` a cada nota.
    private func notesAfterChanging(
        from before: Division, to after: Division, sustain: Int, tempo: Tempo,
        firstWindow: Int64, until horizon: Int64
    ) -> [Note] {
        var scheduler = TrackScheduler(
            timeline: MusicalTimeline(tempo: tempo, division: before),
            material: .cycle(cycle(division: before, sustain: sustain)))
        scheduler.refresh(with: Track(cycle(division: before, sustain: sustain)))
        scheduler.advance(toHorizon: firstWindow, refreshingFrom: nil) { _, _, _, _, _ in }

        scheduler.refresh(with: Track(cycle(division: after, sustain: sustain)))
        var notes: [Note] = []
        scheduler.advance(toHorizon: horizon, refreshingFrom: nil) {
            source, step, _, groove, offset in
            let transportStep = Int64(
                MusicalTimeline(tempo: tempo, division: source!.shape.division)
                    .stepDurationNanoseconds)
            notes.append(
                Note(
                    step: step, onNanoseconds: offset,
                    gateNanoseconds: groove.sustain.gateNanoseconds(over: transportStep)))
        }
        return notes
    }

    // MARK: - Sustain 100%: legato exacto (criterio 8)

    /// **El note-off cae exactamente donde empieza el note-on siguiente**, con
    /// la Division nueva. Con el espaciado en 1/16 y el gate en 1/8, cada nota
    /// habría solapado un Step entero con la siguiente.
    func testFullSustainOnTheNewDivisionIsExactlyLegato() {
        let notes = notesAfterChanging(
            from: .sixteenth, to: .eighth, sustain: 100,
            tempo: Tempo(beatsPerMinute: 120)!,
            firstWindow: 500_000_000, until: 500_000_000 + 8 * 250_000_000)

        XCTAssertGreaterThan(notes.count, 2)
        for (current, next) in zip(notes, notes.dropFirst()) {
            XCTAssertEqual(
                current.offNanoseconds, next.onNanoseconds,
                "el Step \(current.step) no acaba donde empieza el \(next.step)")
        }
    }

    // MARK: - Sustain 200%: el solape que se pide

    /// **Liga sobre el Step siguiente y acaba justo donde empieza el tercero**,
    /// medido en la Division nueva. Si el gate se hubiera quedado en la vieja,
    /// acabaría a mitad del siguiente.
    func testDoubleSustainOverlapsExactlyOneNeighbourOnTheNewDivision() {
        let notes = notesAfterChanging(
            from: .sixteenth, to: .eighth, sustain: 200,
            tempo: Tempo(beatsPerMinute: 120)!,
            firstWindow: 500_000_000, until: 500_000_000 + 8 * 250_000_000)

        XCTAssertGreaterThan(notes.count, 3)
        for (current, afterNext) in zip(notes, notes.dropFirst(2)) {
            XCTAssertEqual(current.gateNanoseconds, 500_000_000)
            XCTAssertEqual(current.offNanoseconds, afterNext.onNanoseconds)
        }
    }

    // MARK: - El extremo del knob

    /// **1/32 a 300 BPM, el Step más corto que `Division.ordered` permite**:
    /// 25 ms. Es donde un desajuste de un Step entre gate y rejilla sería
    /// más grande en proporción.
    func testFullSustainIsExactlyLegatoAtThirtySecondAndThreeHundredBPM() {
        let notes = notesAfterChanging(
            from: .sixteenth, to: .thirtySecond, sustain: 100,
            tempo: Tempo(beatsPerMinute: 300)!,
            firstWindow: 200_000_000, until: 200_000_000 + 16 * 25_000_000)

        XCTAssertGreaterThan(notes.count, 2)
        for (current, next) in zip(notes, notes.dropFirst()) {
            XCTAssertEqual(current.gateNanoseconds, 25_000_000)
            XCTAssertEqual(current.offNanoseconds, next.onNanoseconds)
        }
    }
}
