import XCTest
@testable import Engine

/// Tests de Rotate.
///
/// La Pre Spec lo define como un desplazamiento del patrón que **no cambia
/// Steps ni Pulses**, y más adelante como «el punto de entrada rítmico» del
/// Track. Los tests de aquí comprueban las dos mitades de esa frase: que gira,
/// y que no altera nada más.
final class RotateTests: XCTestCase {

    /// Patrón de referencia: 16/5, uno de los casos de la Pre Spec.
    private static let base = "x..x..x..x..x..."

    // MARK: - Identidad

    func testRotateZeroLeavesThePatternUntouched() {
        XCTAssertEqual(pattern(steps: 16, pulses: 5, rotate: 0), Self.base)
    }

    func testDefaultRotateIsNone() {
        let steps = Steps(16)!
        let unrotated = EuclideanRhythm(steps: steps, pulses: Pulses(5, in: steps)!)
        XCTAssertEqual(unrotated.rotate, .none)
    }

    /// Un giro completo devuelve el anillo a su sitio.
    func testRotateOfAWholeRingIsTheIdentity() {
        XCTAssertEqual(pattern(steps: 16, pulses: 5, rotate: 16), Self.base)
        XCTAssertEqual(pattern(steps: 16, pulses: 5, rotate: 32), Self.base)
        XCTAssertEqual(pattern(steps: 16, pulses: 5, rotate: -16), Self.base)
    }

    // MARK: - Sentido del giro

    /// Rotate positivo empuja el patrón hacia delante en el anillo.
    func testPositiveRotateShiftsThePatternForward() {
        XCTAssertEqual(pattern(steps: 16, pulses: 5, rotate: 1), ".x..x..x..x..x..")
        XCTAssertEqual(pattern(steps: 16, pulses: 5, rotate: 2), "..x..x..x..x..x.")
    }

    /// Rotate negativo gira en sentido contrario, y el Pulse que se sale por el
    /// principio reaparece por el final.
    func testNegativeRotateShiftsThePatternBackward() {
        XCTAssertEqual(pattern(steps: 16, pulses: 5, rotate: -1), "..x..x..x..x...x")
    }

    /// Un giro mayor que el anillo envuelve en lugar de salirse.
    func testRotateGreaterThanStepsWrapsAround() {
        XCTAssertEqual(
            pattern(steps: 16, pulses: 5, rotate: 17),
            pattern(steps: 16, pulses: 5, rotate: 1)
        )
        XCTAssertEqual(
            pattern(steps: 16, pulses: 5, rotate: 101),
            pattern(steps: 16, pulses: 5, rotate: 5)
        )
    }

    // MARK: - Lo que Rotate no cambia

    /// «Rotate desplaza todo el patrón sin cambiar Steps ni Pulses.»
    func testRotatePreservesThePulseCountForEveryValidCombination() {
        for stepCount in Steps.validRange {
            let steps = Steps(stepCount)!
            for pulseCount in 1...stepCount {
                let pulses = Pulses(pulseCount, in: steps)!
                for amount in -20...20 {
                    let rhythm = EuclideanRhythm(steps: steps, pulses: pulses, rotate: Rotate(amount))
                    let triggering = (0..<stepCount).filter { rhythm.triggers(atStep: $0) }
                    XCTAssertEqual(
                        triggering.count,
                        pulseCount,
                        "\(stepCount)/\(pulseCount) rotado \(amount)"
                    )
                }
            }
        }
    }

    func testRotateDoesNotChangeStepsOrPulses() {
        let steps = Steps(12)!
        let pulses = Pulses(7, in: steps)!
        let rhythm = EuclideanRhythm(steps: steps, pulses: pulses, rotate: Rotate(5))
        XCTAssertEqual(rhythm.steps, steps)
        XCTAssertEqual(rhythm.pulses, pulses)
    }

    /// Girar es una permutación del anillo: el patrón girado es el original
    /// leído desde otro punto de entrada, no un reparto distinto.
    func testRotatingIsReadingTheSameRingFromAnotherEntryPoint() {
        let steps = Steps(12)!
        let pulses = Pulses(7, in: steps)!
        let unrotated = EuclideanRhythm(steps: steps, pulses: pulses)

        for amount in -20...20 {
            let rotated = EuclideanRhythm(steps: steps, pulses: pulses, rotate: Rotate(amount))
            for index in 0..<12 {
                XCTAssertEqual(
                    rotated.triggers(atStep: index),
                    unrotated.triggers(atStep: index - amount),
                    "girado \(amount), Step \(index)"
                )
            }
        }
    }

    /// El anillo girado sigue envolviendo hacia arriba y hacia abajo.
    func testRotatedRingStillWrapsOnTheStepIndex() {
        let steps = Steps(16)!
        let rhythm = EuclideanRhythm(steps: steps, pulses: Pulses(5, in: steps)!, rotate: Rotate(3))
        for index in 0..<16 {
            XCTAssertEqual(rhythm.triggers(atStep: index + 16), rhythm.triggers(atStep: index))
            XCTAssertEqual(rhythm.triggers(atStep: index - 16), rhythm.triggers(atStep: index))
        }
    }

    // MARK: - Helper

    private func pattern(steps stepCount: Int, pulses pulseCount: Int, rotate amount: Int) -> String {
        let steps = Steps(stepCount)!
        let rhythm = EuclideanRhythm(
            steps: steps,
            pulses: Pulses(pulseCount, in: steps)!,
            rotate: Rotate(amount)
        )
        return (0..<stepCount).map { rhythm.triggers(atStep: $0) ? "x" : "." }.joined()
    }
}
