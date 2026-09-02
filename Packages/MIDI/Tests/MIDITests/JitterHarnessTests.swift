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

/// Tests de la rejilla que hace avanzar los Cycles.
///
/// **Es la rejilla que la rebanada 3 de la v2 necesita para medirse.** La de
/// `16 Tracks` deja un Cycle por Track, así que mediría los dieciséis quietos:
/// el trabajo que esta rebanada añade —una decisión en el límite de vuelta y un
/// cambio de material justo ahí— no se ejercería nunca.
final class JitterHarnessCyclesGridTests: XCTestCase {

    /// **El material del arnés avanza de Cycle, o la medición no diría nada de
    /// la rebanada 3.** Sin esto, `16 Tracks · 4 Cycles` mediría exactamente lo
    /// mismo que `16 Tracks` y daría un CUMPLE que no ejerce el trabajo nuevo:
    /// la decisión en el límite de vuelta y el cambio de material justo ahí.
    func testTheCyclesGridBuildsTracksThatActuallyAdvance() throws {
        let pattern = try XCTUnwrap(
            JitterHarness.pattern(forTrackCount: 16, groove: nil, cycleCount: 4))

        for index in 0..<16 {
            let track = try XCTUnwrap(pattern.track(at: index))
            XCTAssertEqual(track.activeCount, 4, "el Track \(index + 1) no recorre cuatro")
        }
    }

    /// Y los cuatro Cycles **no son el mismo**: si lo fueran, avanzar no
    /// cambiaría el material y el coste medido sería el de una copia idéntica.
    func testTheFourCyclesCarryDifferentMaterial() throws {
        let pattern = try XCTUnwrap(
            JitterHarness.pattern(forTrackCount: 16, groove: nil, cycleCount: 4))
        let track = try XCTUnwrap(pattern.track(at: 0))

        let pitches = (0..<4).compactMap { track.cycle(at: $0)?.pool.pitch(at: 0)?.value }
        XCTAssertEqual(Set(pitches).count, 4, "los cuatro Cycles llevan la misma altura")
    }

    /// Pero sí comparten Shape: la vuelta tiene que durar lo mismo en los cuatro
    /// y en los dieciséis Tracks, o la medición dejaría de ser comparable con
    /// las anteriores.
    func testTheFourCyclesShareTheirShapeSoTurnsLastTheSame() throws {
        let pattern = try XCTUnwrap(
            JitterHarness.pattern(forTrackCount: 16, groove: nil, cycleCount: 4))
        let track = try XCTUnwrap(pattern.track(at: 0))

        let shapes = (0..<4).compactMap { track.cycle(at: $0)?.shape }
        XCTAssertEqual(Set(shapes.map(\.description)).count, 1)
    }

    /// Por defecto sigue siendo un Cycle por Track, que es lo que mantiene
    /// comparables las rejillas anteriores.
    func testWithoutAskingForCyclesEachTrackKeepsOne() throws {
        let pattern = try XCTUnwrap(JitterHarness.pattern(forTrackCount: 16, groove: nil))

        XCTAssertEqual(pattern.track(at: 0)?.activeCount, 1)
    }

    /// Un solo Track también necesita el camino de Pattern cuando recorre más
    /// de un Cycle; la vía directa no tiene un Track cuyo cursor pueda avanzar.
    func testOneTrackWithSeveralCyclesBuildsAPattern() throws {
        let pattern = try XCTUnwrap(
            JitterHarness.pattern(forTrackCount: 1, groove: nil, cycleCount: 4))

        XCTAssertEqual(pattern.track(at: 0)?.activeCount, 4)
        XCTAssertEqual(pattern.track(at: 1)?.activeCount, 1)
    }
}
