import XCTest
@testable import Engine

/// Tests del reparto euclidiano.
///
/// La Pre Spec fija el criterio —«el H-0 reparte los Pulses lo más
/// uniformemente posible entre los Steps»— y nombra tres casos: 16/4 «muy
/// regular», 16/5 «equilibrio con asimetría», 12/7 «más denso». No escribe los
/// patrones resultantes, así que los de aquí son el registro canónico del
/// proyecto: salen del algoritmo de Bjorklund, que es el que esa frase nombra.
final class EuclideanRhythmTests: XCTestCase {

    // MARK: - Casos literales de la Pre Spec

    /// «16/4 es muy regular»: un Pulse cada cuatro Steps, sin asimetría alguna.
    func testSixteenStepsFourPulses() {
        XCTAssertEqual(pattern(steps: 16, pulses: 4), "x...x...x...x...")
    }

    /// «16/5 conserva equilibrio con asimetría»: cuatro huecos de tres Steps y
    /// uno de cuatro al cerrar el anillo.
    func testSixteenStepsFivePulses() {
        XCTAssertEqual(pattern(steps: 16, pulses: 5), "x..x..x..x..x...")
    }

    /// «12/7 es más denso»: huecos alternos de uno y dos Steps.
    func testTwelveStepsSevenPulses() {
        XCTAssertEqual(pattern(steps: 12, pulses: 7), "x.xx.x.xx.x.")
    }

    // MARK: - Bordes

    func testSinglePulseFallsOnTheFirstStep() {
        XCTAssertEqual(pattern(steps: 16, pulses: 1), "x...............")
    }

    func testPulsesEqualToStepsFillTheRing() {
        XCTAssertEqual(pattern(steps: 8, pulses: 8), "xxxxxxxx")
    }

    func testSingleStepRingAlwaysTriggers() {
        XCTAssertEqual(pattern(steps: 1, pulses: 1), "x")
    }

    // MARK: - Invariantes

    /// El reparto no puede crear ni perder Pulses: repartir n triggers debe
    /// producir exactamente n Steps que disparan, sea cual sea el anillo.
    func testPulseCountIsPreservedForEveryValidCombination() {
        for stepCount in Steps.validRange {
            let steps = Steps(stepCount)!
            for pulseCount in 1...stepCount {
                let rhythm = EuclideanRhythm(steps: steps, pulses: Pulses(pulseCount)!)
                let triggering = (0..<stepCount).filter { rhythm.triggers(atStep: $0) }
                XCTAssertEqual(
                    triggering.count,
                    pulseCount,
                    "\(stepCount)/\(pulseCount) repartió \(triggering.count) Pulses"
                )
            }
        }
    }

    /// El primer Step del anillo siempre dispara: es el punto de entrada del
    /// patrón, y Rotate es lo que lo desplaza.
    func testFirstStepAlwaysTriggers() {
        for stepCount in Steps.validRange {
            let steps = Steps(stepCount)!
            for pulseCount in 1...stepCount {
                let rhythm = EuclideanRhythm(steps: steps, pulses: Pulses(pulseCount)!)
                XCTAssertTrue(rhythm.triggers(atStep: 0), "\(stepCount)/\(pulseCount)")
            }
        }
    }

    // MARK: - Determinismo

    /// Mismo estado, misma salida: el motor no consulta reloj ni aleatorio.
    func testSameConfigurationProducesSamePattern() {
        let first = pattern(steps: 12, pulses: 7)
        for _ in 0..<100 {
            XCTAssertEqual(pattern(steps: 12, pulses: 7), first)
        }
    }

    func testEqualConfigurationsAreEqual() {
        let steps = Steps(16)!
        let pulses = Pulses(5)!
        XCTAssertEqual(
            EuclideanRhythm(steps: steps, pulses: pulses),
            EuclideanRhythm(steps: steps, pulses: pulses)
        )
    }

    // MARK: - El anillo se recorre sin fin

    /// El scheduler cuenta Steps hacia arriba sin parar, así que el índice
    /// envuelve sobre el anillo en lugar de salirse de rango.
    func testStepIndexWrapsAroundTheRing() {
        let rhythm = EuclideanRhythm(steps: Steps(12)!, pulses: Pulses(7)!)
        for index in 0..<12 {
            XCTAssertEqual(rhythm.triggers(atStep: index + 12), rhythm.triggers(atStep: index))
            XCTAssertEqual(rhythm.triggers(atStep: index + 120), rhythm.triggers(atStep: index))
        }
    }

    /// Los índices negativos también envuelven: `MusicalTimeline` ya los admite
    /// para Delay, que desplaza un Track por detrás del origen.
    func testNegativeStepIndexWrapsAroundTheRing() {
        let steps = Steps(16)!
        let rhythm = EuclideanRhythm(steps: steps, pulses: Pulses(5)!)
        for index in 0..<16 {
            XCTAssertEqual(rhythm.triggers(atStep: index - 16), rhythm.triggers(atStep: index))
            XCTAssertEqual(rhythm.triggers(atStep: index - 160), rhythm.triggers(atStep: index))
        }
    }

    // MARK: - Helper

    /// Dibuja el anillo como texto para que los casos de la Pre Spec se lean
    /// igual que se leen en el documento.
    private func pattern(steps stepCount: Int, pulses pulseCount: Int) -> String {
        let steps = Steps(stepCount)!
        let rhythm = EuclideanRhythm(steps: steps, pulses: Pulses(pulseCount)!)
        return (0..<stepCount).map { rhythm.triggers(atStep: $0) ? "x" : "." }.joined()
    }
}
