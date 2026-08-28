import XCTest
@testable import Engine

/// Tests de la geometría del anillo.
///
/// `product-guidelines.md` fija la metáfora —«los Steps se disponen como
/// posiciones en un círculo»— y las dos propiedades que debe hacer evidentes:
/// la naturaleza cíclica del Track y la simetría del reparto euclidiano.
///
/// **Lo que se testea aquí es geometría, no dibujo.** Una posición es una
/// fracción de vuelta en `[0, 1)`; qué píxel le corresponde lo decide quien
/// dibuja, que conoce el tamaño de la pantalla y este tipo no.
final class RingTests: XCTestCase {

    // MARK: - Posiciones

    func testRingHasOnePositionPerStep() {
        for count in Steps.validRange {
            let ring = Ring(shape: shape(steps: count, pulses: 1))
            XCTAssertEqual(ring.positions.count, count, "Steps \(count)")
        }
    }

    /// El reparto es uniforme: la separación entre posiciones consecutivas es
    /// siempre la misma fracción de vuelta.
    func testPositionsAreEvenlySpaced() {
        let ring = Ring(shape: shape(steps: 5, pulses: 1))
        let expected = [0.0, 0.2, 0.4, 0.6, 0.8]

        for (index, fraction) in expected.enumerated() {
            XCTAssertEqual(ring.positions[index].turn, fraction, accuracy: 1e-12, "Step \(index)")
        }
    }

    /// **El Step 0 está clavado.** Si su posición dependiera de cuántos Steps
    /// hay, el anillo entero giraría solo al girar el knob de Steps, y Rotate
    /// dejaría de ser el único que rota.
    func testFirstStepIsAlwaysAtTheStartOfTheTurn() {
        for count in Steps.validRange {
            let ring = Ring(shape: shape(steps: count, pulses: 1))
            XCTAssertEqual(ring.positions[0].turn, 0, "Steps \(count)")
        }
    }

    /// Ninguna posición se sale de la vuelta ni la cierra por duplicado: la
    /// posición 1.0 es la misma que la 0.0.
    func testPositionsStayWithinTheTurn() {
        for count in Steps.validRange {
            let ring = Ring(shape: shape(steps: count, pulses: 1))
            for position in ring.positions {
                XCTAssertGreaterThanOrEqual(position.turn, 0, "Steps \(count)")
                XCTAssertLessThan(position.turn, 1, "Steps \(count)")
            }
        }
    }

    /// Cambiar Steps redistribuye sin dejar huecos ni solapes: las posiciones
    /// salen ordenadas y todas distintas.
    func testChangingStepsRedistributesWithoutGapsOrOverlaps() {
        for count in Steps.validRange {
            let turns = Ring(shape: shape(steps: count, pulses: 1)).positions.map(\.turn)
            XCTAssertEqual(turns, turns.sorted(), "Steps \(count) — desordenadas")
            XCTAssertEqual(Set(turns).count, count, "Steps \(count) — posiciones repetidas")
        }
    }

    // MARK: - Qué posiciones llevan Pulse

    /// Los tres casos que nombra la Pre Spec, leídos desde el anillo en vez de
    /// desde la máscara de bits. Son los mismos patrones que
    /// `EuclideanRhythmTests` fija como registro canónico.
    func testPreSpecCasesMarkTheSamePositions() {
        XCTAssertEqual(marks(steps: 16, pulses: 4), "x...x...x...x...")
        XCTAssertEqual(marks(steps: 16, pulses: 5), "x..x..x..x..x...")
        XCTAssertEqual(marks(steps: 12, pulses: 7), "x.xx.x.xx.x.")
    }

    /// Rotate **desplaza las marcas sobre el anillo**, no reordena el patrón en
    /// el sitio: el conjunto de posiciones no cambia, y las marcadas son las
    /// mismas corridas tantos lugares como diga Rotate.
    func testRotateShiftsTheMarksAroundTheRing() {
        let still = Ring(shape: shape(steps: 8, pulses: 3))
        let turned = Ring(shape: shape(steps: 8, pulses: 3, rotate: 2))

        XCTAssertEqual(still.positions.map(\.turn), turned.positions.map(\.turn))

        let expected = (0..<8).map { still.positions[($0 + 8 - 2) % 8].isPulse }
        XCTAssertEqual(turned.positions.map(\.isPulse), expected)
    }

    /// Con `Pulses > Steps` se marcan los que caben, y el valor pedido no se
    /// pierde: la invariante no destructiva de la rebanada 2 sigue en pie
    /// cuando se mira desde el anillo.
    func testMorePulsesThanStepsMarksOnlyWhatFits() {
        let shape = shape(steps: 4, pulses: 9)
        let ring = Ring(shape: shape)

        XCTAssertEqual(ring.positions.filter(\.isPulse).count, 4)
        XCTAssertEqual(shape.pulses.count, 9, "el valor pedido no se toca")
    }

    /// Invariante exhaustiva: el anillo marca exactamente `effectivePulses`
    /// posiciones, para toda combinación válida.
    func testMarkedPositionsAlwaysMatchEffectivePulses() {
        for steps in Steps.validRange {
            for pulses in Pulses.validRange {
                let shape = shape(steps: steps, pulses: pulses)
                let marked = Ring(shape: shape).positions.filter(\.isPulse).count
                XCTAssertEqual(marked, shape.effectivePulses, "Steps \(steps) · Pulses \(pulses)")
            }
        }
    }

    /// El anillo no recalcula el reparto: dice lo mismo que `EuclideanRhythm`,
    /// que es quien lo sabe.
    func testRingAgreesWithTheRhythmItComesFrom() {
        for steps in Steps.validRange {
            for pulses in Pulses.validRange where pulses <= steps {
                let shape = shape(steps: steps, pulses: pulses, rotate: 3)
                let ring = Ring(shape: shape)

                for index in 0..<steps {
                    XCTAssertEqual(
                        ring.positions[index].isPulse,
                        shape.triggers(atStep: index),
                        "Steps \(steps) · Pulses \(pulses) · Step \(index)"
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func shape(steps: Int, pulses: Int, rotate: Int = 0) -> Shape {
        Shape(steps: Steps(steps)!, pulses: Pulses(pulses)!, rotate: Rotate(rotate))
    }

    /// Dibuja las marcas del anillo con la misma notación que
    /// `EuclideanRhythmTests`, para que los dos registros se puedan comparar a
    /// ojo.
    private func marks(steps: Int, pulses: Int) -> String {
        Ring(shape: shape(steps: steps, pulses: pulses))
            .positions
            .map { $0.isPulse ? "x" : "." }
            .joined()
    }
}
