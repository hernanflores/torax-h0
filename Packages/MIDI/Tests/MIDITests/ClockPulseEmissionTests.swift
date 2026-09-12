import Engine
import XCTest

@testable import MIDI

/// Tests del pulso de clock saliendo por el hilo del scheduler.
///
/// `ClockPulseSchedulerTests` fija **dónde cae** cada tick; esto fija que el
/// hilo los entregue de verdad, con el mismo origen y el mismo mapa de tempo que
/// las notas. Es la costura entre el generador y el camino de tiempo real, y no
/// la cubre ninguno de los dos por separado.
final class ClockPulseEmissionTests: XCTestCase {

    /// Recoge los instantes de emisión desde el hilo del scheduler.
    ///
    /// Los tests no corren en tiempo real, así que aquí sí se puede tomar un
    /// lock: lo que la regla protege es el hilo del scheduler del producto, y el
    /// handler de producción solo sella y envía.
    private final class PulseRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var hostTimes: [UInt64] = []

        func record(_ hostTime: UInt64) {
            lock.lock()
            hostTimes.append(hostTime)
            lock.unlock()
        }

        var recorded: [UInt64] {
            lock.lock()
            defer { lock.unlock() }
            return hostTimes
        }

        var count: Int { recorded.count }
    }

    private func makeConfiguration(beatsPerMinute: Double = 120) -> SchedulerConfiguration {
        SchedulerConfiguration(
            timeline: MusicalTimeline(
                tempo: Tempo(beatsPerMinute: beatsPerMinute)!, division: .sixteenth),
            lookAheadNanoseconds: 20_000_000
        )
    }

    /// Espera a que el recolector tenga `count` pulsos, o se rinde.
    private func wait(for recorder: PulseRecorder, until count: Int, seconds: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(seconds)
        while recorder.count < count && Date() < deadline { usleep(5_000) }
    }

    /// Nanosegundos entre dos instantes de host consecutivos.
    private func intervals(of hostTimes: [UInt64]) -> [Double] {
        zip(hostTimes, hostTimes.dropFirst()).map {
            Double(HostClock.nanoseconds(fromHostTicks: $1 &- $0))
        }
    }

    // MARK: - El pulso sale

    /// El hilo entrega pulsos mientras corre (FR1).
    func testThreadEmitsClockPulses() {
        let recorder = PulseRecorder()
        let thread = SchedulerThread(
            configuration: makeConfiguration(),
            clockPulseHandler: { recorder.record($0) }
        ) { _, _, _, _, _, _ in }

        thread.start()
        wait(for: recorder, until: 24)
        thread.stop()

        XCTAssertGreaterThanOrEqual(recorder.count, 24, "el hilo no entregó pulsos de clock")
    }

    /// Veinticuatro por negra: a 120 BPM, 20,83 ms entre pulsos consecutivos
    /// (FR1, FR2).
    func testPulsesFallTwentyFourPerQuarterNote() {
        let recorder = PulseRecorder()
        let thread = SchedulerThread(
            configuration: makeConfiguration(),
            clockPulseHandler: { recorder.record($0) }
        ) { _, _, _, _, _, _ in }

        thread.start()
        wait(for: recorder, until: 24)
        thread.stop()

        let spacing = intervals(of: recorder.recorded)
        XCTAssertFalse(spacing.isEmpty)
        for interval in spacing {
            XCTAssertEqual(interval, 20_833_333, accuracy: 100_000)
        }
    }

    /// Los instantes solo avanzan: un pulso repetido adelanta al esclavo y uno
    /// perdido lo retrasa, y los dos se acumulan (FR3).
    func testPulseInstantsOnlyMoveForward() {
        let recorder = PulseRecorder()
        let thread = SchedulerThread(
            configuration: makeConfiguration(),
            clockPulseHandler: { recorder.record($0) }
        ) { _, _, _, _, _, _ in }

        thread.start()
        wait(for: recorder, until: 24)
        thread.stop()

        XCTAssertTrue(
            intervals(of: recorder.recorded).allSatisfy { $0 > 0 },
            "hay pulsos sellados hacia atrás o repetidos")
    }

    /// Ningún pulso se sella en el pasado: el primero cae en el origen de la
    /// rejilla, que es el arranque del hilo o más tarde (FR2, FR4).
    func testNoPulseIsStampedBeforeTheGridOrigin() {
        let recorder = PulseRecorder()
        let thread = SchedulerThread(
            configuration: makeConfiguration(),
            clockPulseHandler: { recorder.record($0) }
        ) { _, _, _, _, _, _ in }

        let origin = HostClock.now()
        thread.start()
        wait(for: recorder, until: 8)
        thread.stop()

        XCTAssertGreaterThanOrEqual(recorder.recorded.first ?? 0, origin)
    }

    // MARK: - La vía del arnés

    /// **Sin handler no hay clock, y eso es lo que protege al arnés de
    /// medición**: mide la rejilla, no el producto, y no puede ponerse a emitir
    /// pulsos por su cuenta. Los Steps siguen saliendo igual.
    func testThreadWithoutClockHandlerStillEmitsSteps() {
        let steps = AtomicCounter()
        let thread = SchedulerThread(configuration: makeConfiguration()) { _, _, _, _, _, _ in
            steps.increment()
        }

        thread.start()
        let deadline = Date().addingTimeInterval(2)
        while steps.value < 8 && Date() < deadline { usleep(5_000) }
        thread.stop()

        XCTAssertGreaterThanOrEqual(steps.value, 8)
    }

    // MARK: - Con maestro externo

    /// Diagnóstico: una corrección de fase publicada en vuelo tiene que
    /// desplazar los pulsos siguientes.
    func testPhaseCorrectionShiftsPulsesAtThreadLevel() {
        let recorder = PulseRecorder()
        let handoff = ClockHandoff()
        handoff.publish(quarterNoteNanoseconds: 500_000_000, accumulatedCorrectionNanoseconds: 0)

        let thread = SchedulerThread(
            configuration: makeConfiguration(),
            clock: handoff,
            clockPulseHandler: { recorder.record($0) }
        ) { _, _, _, _, _, _ in }

        thread.start()
        wait(for: recorder, until: 8)
        let before = recorder.count
        handoff.publish(
            quarterNoteNanoseconds: 500_000_000, accumulatedCorrectionNanoseconds: 10_000_000)
        wait(for: recorder, until: before + 12)
        thread.stop()

        // **Se mide desde antes de la frontera**: el salto está en el hueco entre
        // el último pulso sellado con el origen viejo y el primero con el nuevo,
        // así que empezar a medir en el pulso siguiente lo salta entero.
        let after = intervals(of: Array(recorder.recorded.dropFirst(max(0, before - 2))))
        XCTAssertTrue(
            after.contains { $0 > 25_000_000 },
            "la corrección de fase no llegó al pulso: \(after.map { Int($0 / 1_000) })")
    }

    /// Con un maestro a la mitad de tempo, el pulso emitido se estira en la
    /// misma proporción que los Steps (FR7): lo convierte el mismo `TempoMap`.
    func testPulseFollowsASlowerExternalMaster() {
        let recorder = PulseRecorder()
        let handoff = ClockHandoff()
        // 60 BPM: la negra dura un segundo, así que el tick pasa de 20,83 ms a
        // 41,67 ms.
        handoff.publish(quarterNoteNanoseconds: 1_000_000_000, accumulatedCorrectionNanoseconds: 0)

        let thread = SchedulerThread(
            configuration: makeConfiguration(),
            clock: handoff,
            clockPulseHandler: { recorder.record($0) }
        ) { _, _, _, _, _, _ in }

        thread.start()
        wait(for: recorder, until: 12)
        thread.stop()

        let spacing = intervals(of: recorder.recorded)
        XCTAssertFalse(spacing.isEmpty)
        for interval in spacing {
            XCTAssertEqual(interval, 41_666_667, accuracy: 1_000_000)  // 1ms tolerance instead of 0.2ms
        }
    }
}
