import XCTest
@testable import Engine

/// Tests del acotado no destructivo de Pulses.
///
/// La regla viene de `product-guidelines.md`: «cambiar un parámetro nunca
/// destruye material». Girar Steps hacia abajo tiene que acotar lo que suena,
/// no borrar lo que se pidió — igual que el pool tonal sobrevive a un cambio de
/// Scale reencuadrándose y no vaciándose.
final class NonDestructiveClampTests: XCTestCase {

    private func pattern(steps stepCount: Int, pulses pulseCount: Int) -> String {
        let rhythm = EuclideanRhythm(steps: Steps(stepCount)!, pulses: Pulses(pulseCount)!)
        return (0..<stepCount).map { rhythm.triggers(atStep: $0) ? "x" : "." }.joined()
    }

    // MARK: - Se acota lo que suena, no lo que se guarda

    func testMorePulsesThanStepsFillsTheRing() {
        XCTAssertEqual(pattern(steps: 4, pulses: 9), "xxxx")
    }

    func testTheIntendedValueSurvivesTheClamp() {
        let shape = Shape(steps: Steps(4)!, pulses: Pulses(9)!)
        XCTAssertEqual(shape.pulses.count, 9, "se perdió lo que el usuario pidió")
        XCTAssertEqual(shape.effectivePulses, 4, "sonaron más Pulses de los que caben")
    }

    func testEffectivePulsesEqualsIntendedWhenItFits() {
        let shape = Shape(steps: Steps(16)!, pulses: Pulses(5)!)
        XCTAssertEqual(shape.pulses.count, 5)
        XCTAssertEqual(shape.effectivePulses, 5)
    }

    // MARK: - Ida y vuelta

    /// El caso que motiva la regla: girar Steps de 16 a 4 y volver a subirlo no
    /// puede costar la configuración.
    func testTurningStepsDownAndBackUpRestoresThePattern() {
        let original = pattern(steps: 16, pulses: 9)

        // Por el camino, con Steps 4, solo caben 4.
        XCTAssertEqual(pattern(steps: 4, pulses: 9), "xxxx")

        XCTAssertEqual(pattern(steps: 16, pulses: 9), original, "no se recuperó el patrón")
    }

    /// Lo mismo recorriendo todo el rango hacia abajo y hacia arriba, como haría
    /// un giro largo de knob.
    func testASweepDownAndUpIsLossless() {
        let intended = Pulses(12)!
        let original = EuclideanRhythm(steps: Steps(16)!, pulses: intended)

        for stepCount in stride(from: 16, through: 1, by: -1) {
            _ = EuclideanRhythm(steps: Steps(stepCount)!, pulses: intended)
        }
        for stepCount in 1...16 {
            _ = EuclideanRhythm(steps: Steps(stepCount)!, pulses: intended)
        }

        XCTAssertEqual(EuclideanRhythm(steps: Steps(16)!, pulses: intended), original)
    }

    // MARK: - Invariante

    /// Para toda combinación de Steps y Pulses, incluidas las que no caben:
    /// suenan exactamente `min(pulses, steps)` y el valor pedido se conserva.
    func testEffectivePulsesIsAlwaysTheMinimumForEveryCombination() {
        for stepCount in Steps.validRange {
            for pulseCount in Pulses.validRange {
                let steps = Steps(stepCount)!
                let pulses = Pulses(pulseCount)!
                let rhythm = EuclideanRhythm(steps: steps, pulses: pulses)
                let triggering = (0..<stepCount).filter { rhythm.triggers(atStep: $0) }

                XCTAssertEqual(
                    rhythm.effectivePulses,
                    min(pulseCount, stepCount),
                    "\(stepCount)/\(pulseCount)"
                )
                XCTAssertEqual(
                    triggering.count,
                    rhythm.effectivePulses,
                    "\(stepCount)/\(pulseCount) repartió \(triggering.count)"
                )
                XCTAssertEqual(rhythm.pulses.count, pulseCount, "se perdió la intención")
            }
        }
    }

    /// El primer Step sigue disparando también cuando se acota.
    func testFirstStepStillTriggersWhenClamped() {
        for stepCount in Steps.validRange {
            for pulseCount in Pulses.validRange {
                let rhythm = EuclideanRhythm(steps: Steps(stepCount)!, pulses: Pulses(pulseCount)!)
                XCTAssertTrue(rhythm.triggers(atStep: 0), "\(stepCount)/\(pulseCount)")
            }
        }
    }

    // MARK: - Lo que se muestra

    /// La pantalla muestra **lo que se pidió**, no lo que cabe.
    ///
    /// `product-guidelines.md` dice que el estado del software es la única
    /// fuente de verdad del knob y que la posición física es irrelevante: el
    /// valor del parámetro es el pretendido. Que solo suenen 4 de 9 lo hará
    /// evidente el anillo cuando llegue; el texto no es el sitio donde
    /// desambiguarlo.
    func testDescriptionShowsTheIntendedPulses() {
        let shape = Shape(steps: Steps(4)!, pulses: Pulses(9)!)
        XCTAssertEqual(shape.description, "Steps 4 · Pulses 9 · Rotate 0 · Division 1/16")
    }
}
