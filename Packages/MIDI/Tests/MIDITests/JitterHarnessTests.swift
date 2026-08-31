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
            print(
                "[jitter macOS \(Int(measurement.beatsPerMinute)) BPM] \(measurement.statistics.summary)"
            )
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
            guard case JitterHarnessError.timedOut(let collected, let expected) = error else {
                return XCTFail("Se esperaba timedOut, llego \(error)")
            }
            XCTAssertEqual(expected, 10_000)
            XCTAssertLessThan(collected, 10_000)
        }
    }
}

/// Tests del arnés corriendo con un Groove desplazado.
///
/// **Sin CoreMIDI de por medio.** Lo que se comprueba es la elección de
/// material, que es lógica pura; la medición de verdad exige dispositivo y es la
/// Fase 6 del track.
final class JitterHarnessGrooveTests: XCTestCase {

    /// **Sin Groove, el camino de siempre.** La medición de regresión tiene que
    /// poder compararse contra las de las rebanadas anteriores sin asteriscos, y
    /// para eso tiene que recorrer exactamente el mismo código.
    func testWithoutAGrooveTheHarnessKeepsItsEveryStepMode() {
        XCTAssertEqual(JitterHarness.material(for: nil), .everyStep)
    }

    /// Con Groove, un anillo lleno: todos los Steps siguen disparando, así que
    /// no se pierden muestras del histograma.
    func testWithAGrooveEveryStepStillTriggers() {
        let swung = Groove(
            velocity: .default,
            sustain: .default,
            probability: .default,
            timing: Timing(percent: 75)!,
            delay: .default
        )

        let material = JitterHarness.material(for: swung)

        for step in 0..<16 {
            XCTAssertTrue(material.triggers(atStep: step), "el Step \(step) no dispara")
        }
        XCTAssertEqual(material.groove, swung)
    }

    /// Y sigue sonando siempre la misma altura: dos muestras solo se
    /// diferencian en cuándo salieron.
    func testWithAGrooveThePitchIsStillConstant() {
        let material = JitterHarness.material(for: .default)

        for step in 0..<16 {
            XCTAssertEqual(material.pitch(atStep: step), SchedulerMaterial.measurementPitch)
        }
    }

    /// El default explícito **no** es lo mismo que no pasar nada: uno recorre el
    /// camino de un Track y el otro el modo del arnés. Los dos dejan la rejilla
    /// recta, y eso es lo que hace comparable la medición.
    func testTheDefaultGrooveStillLeavesTheGridStraight() {
        let material = JitterHarness.material(for: .default)

        XCTAssertNotEqual(material, .everyStep)
        for step in 0..<16 {
            XCTAssertEqual(
                material.groove.shiftNanoseconds(
                    atStep: step, stepDurationNanoseconds: 125_000_000),
                0
            )
        }
    }

    func testTheConfigurationCarriesNoGrooveByDefault() {
        let configuration = JitterMeasurementConfiguration(tempo: Tempo(beatsPerMinute: 120)!)
        XCTAssertNil(configuration.groove)
    }
}
