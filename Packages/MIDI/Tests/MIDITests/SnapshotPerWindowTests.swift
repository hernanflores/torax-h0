import Engine
import Foundation
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre en los
/// targets de test.
private typealias Pattern = Engine.Pattern

/// Tests de cuántas veces se copia el snapshot mientras suena.
///
/// **El snapshot se recoge una vez por ventana, no una por evento.** El
/// scheduler ya lo hacía —`PatternScheduler` lo documenta— pero el emisor lo
/// releía por cada nota para saber por qué canal salía y cuánto duraba el Step.
/// Con un Pattern de 2,25 KB esa lectura de más era invisible; con Cycles el
/// snapshot se multiplica por dieciséis y pasa a ser una copia de decenas de
/// kilobytes **por nota**, dentro del hilo de tiempo real.
///
/// Por eso esto es una corrección y no una optimización prematura: se arregla
/// antes de que el modelo crezca, no después de que se oiga.
final class SnapshotPerWindowTests: XCTestCase {

    /// Recoge lo que sale, desde el hilo del scheduler.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [MIDIMessage] = []

        func record(_ message: MIDIMessage, _ hostTime: UInt64) {
            lock.withLock { messages.append(message) }
        }

        var noteOnCount: Int {
            lock.withLock {
                messages.filter { if case .noteOn = $0 { true } else { false } }.count
            }
        }

        func noteOnCount(onChannel number: Int) -> Int {
            lock.withLock {
                messages.filter {
                    if case .noteOn(let channel, _, _) = $0 {
                        channel.number == number
                    } else {
                        false
                    }
                }.count
            }
        }
    }

    /// Un Track que dispara en todos sus Steps: el test no tiene que esperar al
    /// reparto euclidiano para acumular eventos.
    private func voice(onChannel number: Int, division: Division = .sixteenth) -> Track {
        Track(
            shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!, division: division),
            pool: PitchPool().inserting(Pitch(48)!),
            channel: Channel(number)!
        )
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 6) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(2_000) }
    }

    /// **La comprobación de la fase, y por qué está en un solo Play.**
    ///
    /// Cada reproducción arranca un hilo a prioridad máxima, y acumularlos en un
    /// mismo proceso es la condición que dispara `midi-test-flake` (la
    /// ampliación del 2026-08-30 de `workflow.md`). Así que las dos preguntas de
    /// esta tarea —cuántas veces se lee el snapshot, y que cambiar el canal se
    /// siga oyendo— se responden dentro de la misma reproducción.
    ///
    /// Ocho Tracks con material sobre una ventana de 100 ms dan del orden de
    /// dieciséis eventos por ventana, así que «una lectura por ventana» y «una
    /// por evento» se separan por más de un orden de magnitud y la cota no
    /// depende de cuántas vueltas dé el hilo.
    func testTheSnapshotIsReadOncePerWindowAndNotOncePerEvent() throws {
        let recorder = Recorder()
        // 300 BPM con Division 1/16 da Steps de 50 ms; con 100 ms de ventana
        // caben dos Steps de cada Track en cada vuelta del bucle.
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth)
        var pattern = Pattern()
        for index in 0..<8 {
            pattern = pattern.replacing(voice(onChannel: index + 1), at: index)
        }

        let transport = Transport(
            configuration: SchedulerConfiguration(
                timeline: timeline,
                lookAheadNanoseconds: 100_000_000
            ),
            pattern: pattern,
            emitter: NoteEmitter(),
            send: recorder.record
        )

        transport.play()
        waitUntil { recorder.noteOnCount >= 160 }

        // El canal cambia mientras suena, y se tiene que oír: es la razón por la
        // que la lectura por evento existía, y no se puede perder al quitarla.
        // El canal 12 está libre —solo hay material en los ocho primeros
        // Tracks— así que cualquier nota que salga por ahí es ésta.
        let beforeChange = recorder.noteOnCount
        transport.publish(pattern.replacing(voice(onChannel: 12), at: 0))
        waitUntil { recorder.noteOnCount(onChannel: 12) > 0 }

        transport.stop()

        let events = recorder.noteOnCount
        let loads = try XCTUnwrap(transport.handoffLoadCount)

        XCTAssertGreaterThan(events, beforeChange, "dejó de emitir al publicar")
        XCTAssertGreaterThan(
            recorder.noteOnCount(onChannel: 12), 0,
            "cambiar el canal mientras suena dejó de oírse")
        XCTAssertLessThan(
            loads, UInt64(events / 4),
            "el snapshot se está leyendo por evento y no por ventana: \(loads) lecturas "
                + "para \(events) notas")
    }

    /// El canal y la Division con que sale una nota son los del **mismo**
    /// snapshot que produjo el evento, no los del que esté publicado cuando le
    /// toque salir.
    ///
    /// Se comprueba sin hilos: publicar desde dentro del emisor es la única
    /// forma de que una publicación caiga exactamente a mitad de ventana, que es
    /// el instante en el que dos lecturas discreparían.
    func testEveryEventOfAWindowCarriesTheSnapshotThatProducedIt() {
        let tempo = Tempo(beatsPerMinute: 120)!
        let stepNanoseconds: Int64 = 125_000_000
        let pattern = Pattern().replacing(voice(onChannel: 3), at: 0)
        let handoff = PatternHandoff(pattern)
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern)

        var channels: [Int] = []
        scheduler.advance(toHorizon: 8 * stepNanoseconds, refreshingFrom: handoff) {
            _, source, _, _, _, _ in
            // A mitad de ventana se publica otro canal. Lo que sale detrás tiene
            // que seguir siendo lo que la ventana empezó a tocar.
            handoff.publish(pattern.replacing(self.voice(onChannel: 9), at: 0))
            channels.append(source.channel.number)
        }

        XCTAssertGreaterThan(channels.count, 1, "una sola nota no distingue nada")
        XCTAssertEqual(
            Set(channels), [3],
            "una nota salió por el canal de una publicación posterior a su evento")
    }

    /// Y la publicación de la ventana anterior sí se recoge en la siguiente: no
    /// se ha cambiado «se lee una vez por ventana» por «no se lee».
    func testThePublishedSnapshotIsPickedUpOnTheNextWindow() {
        let tempo = Tempo(beatsPerMinute: 120)!
        let stepNanoseconds: Int64 = 125_000_000
        let pattern = Pattern().replacing(voice(onChannel: 3), at: 0)
        let handoff = PatternHandoff(pattern)
        let scheduler = PatternScheduler(tempo: tempo, pattern: pattern)

        scheduler.advance(toHorizon: 4 * stepNanoseconds, refreshingFrom: handoff) {
            _, _, _, _, _, _ in
        }
        handoff.publish(pattern.replacing(voice(onChannel: 9), at: 0))

        var channels: [Int] = []
        scheduler.advance(toHorizon: 8 * stepNanoseconds, refreshingFrom: handoff) {
            _, source, _, _, _, _ in
            channels.append(source.channel.number)
        }

        XCTAssertEqual(Set(channels), [9], "la publicación no llegó a la ventana siguiente")
    }
}
