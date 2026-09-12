import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del pulso cuando el tempo cambia con el transporte corriendo.
///
/// **Es la costura que ninguna de las fases anteriores cubre.** El generador
/// sabe dónde cae cada tick y el hilo sabe entregarlo, pero el tempo puede
/// cambiar por tres puertas —el knob, el Bank y el maestro externo— y las tres
/// terminan en el mismo sitio: `ClockHandoff`. Lo que se comprueba aquí es que
/// el pulso emitido las obedezca **sin reiniciar la cuenta ni saltar de fase**.
final class ClockMasterTempoTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(message: MIDIMessage, hostTime: UInt64)] = []

        func record(_ message: MIDIMessage, _ hostTime: UInt64) {
            lock.withLock { entries.append((message, hostTime)) }
        }

        var pulses: [UInt64] {
            lock.withLock { entries.filter { $0.message == .timingClock }.map(\.hostTime) }
        }
    }

    private func makeTransport(_ recorder: Recorder, beatsPerMinute: Double = 120) -> Transport {
        Transport(
            configuration: SchedulerConfiguration(
                timeline: MusicalTimeline(
                    tempo: Tempo(beatsPerMinute: beatsPerMinute)!, division: .sixteenth),
                lookAheadNanoseconds: 20_000_000
            ),
            pattern: Pattern.initial,
            emitter: NoteEmitter(),
            send: recorder.record
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(5_000) }
    }

    private func intervals(of hostTimes: [UInt64]) -> [Double] {
        zip(hostTimes, hostTimes.dropFirst()).map {
            Double(HostClock.nanoseconds(fromHostTicks: $1 &- $0))
        }
    }

    /// Los pulsos que llegan **después** de que el cambio haya podido entrar.
    ///
    /// Se descartan cuatro: los que ya estaban sellados cuando el tempo cambió
    /// llevan el espaciado viejo, y eso no es un fallo — es lo que significa
    /// sellar hacia el futuro.
    private func settledIntervals(of recorder: Recorder, after count: Int) -> [Double] {
        intervals(of: Array(recorder.pulses.dropFirst(count + 4)))
    }

    private func bank(_ beatsPerMinute: Double) -> Bank {
        Bank()
            .replacing(
                Pattern().replacing(
                    Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!)), at: 0),
                at: 0
            )
            .withTempo(Tempo(beatsPerMinute: beatsPerMinute)!)
    }

    // MARK: - El knob de tempo

    /// Bajar el tempo a la mitad con el transporte corriendo separa el doble los
    /// pulsos siguientes, **sin reiniciar la cuenta** (FR10).
    func testTheTempoKnobStretchesThePulseInFlight() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.pulses.count >= 12 }
        let before = recorder.pulses.count

        XCTAssertTrue(transport.setTempo(beatsPerMinute: 60))
        waitUntil { recorder.pulses.count >= before + 16 }
        transport.stop()

        let settled = settledIntervals(of: recorder, after: before)
        XCTAssertFalse(settled.isEmpty, "no llegaron pulsos después del cambio")
        for interval in settled.prefix(8) {
            XCTAssertEqual(interval, 41_666_667, accuracy: 1_000_000)
        }
    }

    /// El pulso nunca retrocede al cambiar de tempo: la marca de agua solo
    /// avanza, así que el esclavo no recibe un tick repetido (FR3, FR10).
    func testThePulseNeverGoesBackwardsWhenTheTempoChanges() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.pulses.count >= 12 }
        XCTAssertTrue(transport.setTempo(beatsPerMinute: 200))
        waitUntil { recorder.pulses.count >= 30 }
        transport.stop()

        XCTAssertTrue(
            intervals(of: recorder.pulses).allSatisfy { $0 > 0 },
            "hay pulsos sellados hacia atrás o repetidos al cambiar el tempo")
    }

    // MARK: - El Bank

    /// Cambiar de Bank lleva su tempo al pulso: una sola regla en el producto, y
    /// el esclavo la obedece como la obedece la app.
    func testChangingBankCarriesItsTempoToThePulse() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)

        transport.play()
        waitUntil { recorder.pulses.count >= 12 }
        let before = recorder.pulses.count

        transport.select(bank(60), pattern: 0)
        waitUntil { recorder.pulses.count >= before + 16 }
        transport.stop()

        let settled = settledIntervals(of: recorder, after: before)
        XCTAssertFalse(settled.isEmpty)
        for interval in settled.prefix(8) {
            XCTAssertEqual(interval, 41_666_667, accuracy: 1_000_000)
        }
    }

    // MARK: - El maestro externo

    /// Con `External`, el tempo del maestro llega al pulso emitido en vuelo
    /// (FR7): lo convierte el mismo `TempoMap` que los Steps.
    func testAnExternalMasterStretchesThePulseInFlight() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        transport.clockSource = .external

        transport.play()
        waitUntil { recorder.pulses.count >= 12 }
        let before = recorder.pulses.count

        // 60 BPM: la negra dura un segundo.
        transport.clockHandoff.publish(
            quarterNoteNanoseconds: 1_000_000_000, accumulatedCorrectionNanoseconds: 0)
        waitUntil { recorder.pulses.count >= before + 16 }
        transport.stop()

        let settled = settledIntervals(of: recorder, after: before)
        XCTAssertFalse(settled.isEmpty)
        for interval in settled.prefix(8) {
            XCTAssertEqual(interval, 41_666_667, accuracy: 1_000_000)
        }
    }

    /// **Las correcciones de fase del maestro también desplazan el pulso.** Sin
    /// esto, el clock emitido se separaría poco a poco del recibido aunque el
    /// tempo coincidiera: es la deriva que el re-anclaje por negra existe para
    /// corregir.
    func testAPhaseCorrectionShiftsThePulse() {
        let recorder = Recorder()
        let transport = makeTransport(recorder)
        transport.clockSource = .external
        transport.clockHandoff.publish(
            quarterNoteNanoseconds: 500_000_000, accumulatedCorrectionNanoseconds: 0)

        transport.play()
        waitUntil { recorder.pulses.count >= 12 }
        let before = recorder.pulses.count

        // Diez milisegundos de corrección acumulada: medio tick largo, así que
        // un hueco tiene que crecer visiblemente.
        transport.clockHandoff.publish(
            quarterNoteNanoseconds: 500_000_000, accumulatedCorrectionNanoseconds: 10_000_000)
        waitUntil { recorder.pulses.count >= before + 12 }
        transport.stop()

        // **Se mide desde antes de la frontera.** El salto vive en el hueco entre
        // el último pulso sellado con el origen viejo y el primero con el nuevo:
        // empezar a medir en el pulso siguiente se lo salta entero, que es el
        // error que costó una vuelta de diagnóstico.
        let after = intervals(of: Array(recorder.pulses.dropFirst(max(0, before - 2))))
        XCTAssertTrue(
            after.contains { $0 > 25_000_000 },
            "la corrección de fase no llegó al pulso emitido: \(after.map { Int($0 / 1_000) })")
    }
}
