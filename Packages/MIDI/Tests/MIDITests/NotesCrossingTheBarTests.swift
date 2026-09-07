import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de que una nota que cruza el cambio de Pattern termine (FR9).
///
/// **Sin all-notes-off en el límite, y a propósito.** El note-off ya viaja
/// sellado con su note-on por el look-ahead, así que la nota termina cuando
/// tenía que terminar aunque su Pattern ya no esté. La cola de la frase anterior
/// se solapa con la nueva, que es lo que hace cualquier secuenciador; cortarla
/// en seco se oye.
///
/// **Esta tarea es una comprobación, no una implementación.** El plan lo decía:
/// «puede que no haga falta código». Hace falta el test, porque la propiedad de
/// la que depende —que el par note-on/note-off se emita junto— es fácil de
/// romper sin darse cuenta el día que alguien mueva la emisión.
final class NotesCrossingTheBarTests: XCTestCase {

    private let tempo = Tempo(beatsPerMinute: 120)!

    /// Un Pattern cuyas notas duran mucho más que un Step: con Sustain al 100%
    /// cada nota llega justo a la siguiente, y con Division lenta la nota del
    /// último Step del compás sigue sonando cuando entra el Pattern nuevo.
    private func sustained(pitch value: Int) -> Pattern {
        Pattern().replacing(
            Cycle(
                shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!, division: .quarter),
                pool: PitchPool().inserting(Pitch(value)!),
                groove: Groove(
                    velocity: .default,
                    sustain: Sustain(percent: 100)!,
                    probability: .default
                )
            ),
            at: 0
        )
    }

    /// Todos los mensajes que salen hasta ese horizonte, con su instante.
    private func messages(
        upTo horizon: Int64, from scheduler: PatternScheduler, handoff: PatternHandoff
    ) -> [(message: MIDIMessage, hostTime: UInt64)] {
        let emitter = NoteEmitter()
        var collected: [(MIDIMessage, UInt64)] = []

        scheduler.advance(toHorizon: horizon, refreshingFrom: handoff) {
            _, source, _, pitch, groove, offset in
            emitter.emit(
                pitch: pitch,
                groove: groove,
                on: MIDIChannel(source.channel),
                stepDurationNanoseconds: 500_000_000,
                // **En ticks de host, no en nanosegundos.** `NoteEmitter`
                // convierte el gate a ticks, así que darle un instante en
                // nanosegundos mezclaría dos unidades y el apagado caería en
                // cualquier sitio. Es el error que este test cometió primero.
                atHostTime: HostClock.hostTicks(fromNanoseconds: UInt64(max(0, offset)))
            ) { message, hostTime in
                collected.append((message, hostTime))
            }
        }
        return collected.map { (message: $0.0, hostTime: $0.1) }
    }

    private func notes(_ collected: [(message: MIDIMessage, hostTime: UInt64)]) -> (
        on: [UInt8], off: [UInt8]
    ) {
        var on: [UInt8] = []
        var off: [UInt8] = []
        for entry in collected {
            switch entry.message {
            case .noteOn(_, let note, _): on.append(note.value)
            case .noteOff(_, let note, _): off.append(note.value)
            default: break
            }
        }
        return (on, off)
    }

    /// **Cada note-on tiene su note-off**, cruce o no cruce.
    func testEveryNoteOnHasItsNoteOff() {
        let handoff = PatternHandoff(sustained(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: sustained(pitch: 60))

        handoff.arm(sustained(pitch: 72))
        let (on, off) = notes(messages(upTo: 4_000_000_000, from: scheduler, handoff: handoff))

        XCTAssertFalse(on.isEmpty)
        XCTAssertEqual(on.sorted(), off.sorted(), "quedó alguna nota sin apagar")
    }

    /// **La nota del Pattern viejo recibe su note-off después del límite**, que
    /// es exactamente el caso que la tarea existe para comprobar.
    func testTheLastNoteOfTheOldPatternIsTurnedOffAfterTheBoundary() {
        let handoff = PatternHandoff(sustained(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: sustained(pitch: 60))

        handoff.arm(sustained(pitch: 72))
        let collected = messages(upTo: 4_000_000_000, from: scheduler, handoff: handoff)

        let offsAfterBoundary = collected.filter {
            if case .noteOff(_, let note, _) = $0.message {
                return note.value == 60
                    && $0.hostTime >= HostClock.hostTicks(fromNanoseconds: 2_000_000_000)
            }
            return false
        }

        XCTAssertFalse(
            offsAfterBoundary.isEmpty,
            "la nota del Pattern viejo no recibió su apagado tras el cambio")
    }

    /// **No hay all-notes-off en el límite.** Si lo hubiera, aparecerían
    /// apagados de notas que nunca sonaron o un apagado por canal.
    func testThereIsNoAllNotesOffAtTheBoundary() {
        let handoff = PatternHandoff(sustained(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: sustained(pitch: 60))

        handoff.arm(sustained(pitch: 72))
        let (on, off) = notes(messages(upTo: 4_000_000_000, from: scheduler, handoff: handoff))

        XCTAssertEqual(Set(off).subtracting(Set(on)), [], "se apagó una nota que nunca sonó")
        XCTAssertEqual(on.count, off.count)
    }

    /// **Diez cambios seguidos y ninguna nota queda colgada.** Es el caso de
    /// directo: alternar entre dos Patterns compás tras compás.
    func testTenChangesInARowLeaveNothingHanging() {
        let handoff = PatternHandoff(sustained(pitch: 60))
        let scheduler = PatternScheduler(tempo: tempo, pattern: sustained(pitch: 60))

        var collected: [(message: MIDIMessage, hostTime: UInt64)] = []
        for index in 0..<10 {
            handoff.arm(sustained(pitch: index.isMultiple(of: 2) ? 72 : 60))
            let horizon = Int64(index + 1) * 2_000_000_000
            collected += messages(upTo: horizon, from: scheduler, handoff: handoff)
        }

        let (on, off) = notes(collected)
        XCTAssertGreaterThan(on.count, 10)
        XCTAssertEqual(on.sorted(), off.sorted(), "alguna nota quedó colgada tras diez cambios")
    }
}
