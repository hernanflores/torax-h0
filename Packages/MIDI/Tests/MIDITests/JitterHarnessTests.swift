import Engine
import XCTest
@testable import MIDI

/// Tests del arnés de medición completo.
///
/// Estas mediciones corren en **macOS**, no en el iPad. Sirven para comprobar
/// que el arnés funciona de punta a punta y para tener una señal temprana, pero
/// **no son el veredicto del track**: el iPad es otra máquina, con otro
/// planificador y otras restricciones de energía. La spec exige medir allí.
final class JitterHarnessTests: XCTestCase {

    /// Muestra pequeña para que la suite siga siendo rápida: a 120 BPM en 1/16,
    /// 32 eventos son unos 4 segundos.
    private let sampleCount = 32

    func testHarnessCollectsTheRequestedNumberOfSamples() throws {
        let statistics = try JitterHarness.measure(
            JitterMeasurementConfiguration(
                tempo: Tempo(beatsPerMinute: 120)!,
                sampleCount: sampleCount,
                timeoutSeconds: 30
            )
        )
        XCTAssertEqual(statistics.sampleCount, sampleCount)
        print("[jitter macOS 120 BPM] \(statistics.summary)")
    }

    /// El barrido debe devolver una medición por tempo.
    func testSweepReturnsOneMeasurementPerTempo() throws {
        let measurements = try JitterHarness.sweep(
            tempos: [60, 120, 174],
            sampleCount: sampleCount,
            timeoutSeconds: 30
        )
        XCTAssertEqual(measurements.count, 3)
        for measurement in measurements {
            print("[jitter macOS \(Int(measurement.beatsPerMinute)) BPM] \(measurement.statistics.summary)")
        }
    }

    /// Un tempo fuera del rango válido se descarta en lugar de romper el
    /// barrido.
    func testSweepSkipsInvalidTempos() throws {
        let measurements = try JitterHarness.sweep(
            tempos: [120, 5_000],
            sampleCount: sampleCount,
            timeoutSeconds: 30
        )
        XCTAssertEqual(measurements.count, 1)
    }

    /// Un plazo imposible debe reportar cuántas muestras se llegaron a reunir,
    /// no fallar en silencio.
    func testTimeoutReportsPartialProgress() {
        XCTAssertThrowsError(
            try JitterHarness.measure(
                JitterMeasurementConfiguration(
                    tempo: Tempo(beatsPerMinute: 60)!,
                    sampleCount: 10_000,
                    timeoutSeconds: 0.5
                )
            )
        ) { error in
            guard case let JitterHarnessError.timedOut(collected, expected) = error else {
                return XCTFail("Se esperaba timedOut, llego \(error)")
            }
            XCTAssertEqual(expected, 10_000)
            XCTAssertLessThan(collected, 10_000)
        }
    }
}
