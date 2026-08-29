import XCTest

@testable import Engine

/// Tests de los tipos de Groove.
///
/// Mismo criterio que `ShapeTypesTests`: la validación vive en el
/// inicializador, no en cada sitio de uso (`conductor/code_styleguides/swift.md`).
/// Un `Velocity` que existe es siempre emisible; un `Sustain` que existe es
/// siempre una duración musical razonable.
final class GrooveTypesTests: XCTestCase {

    // MARK: - Velocity

    func testVelocityAcceptsTheWholeValidRange() {
        for value in 1...127 {
            XCTAssertEqual(Velocity(value)?.value, value)
        }
    }

    /// **El cero no es un nivel dinámico.** En MIDI 1.0 un note-on con velocity
    /// 0 es la convención de apagado, así que admitirlo aquí dejaría que un
    /// parámetro de dinámica produjera silencio por una vía que el resto del
    /// código lee como note-off.
    func testVelocityRejectsZero() {
        XCTAssertNil(Velocity(0))
    }

    func testVelocityRejectsValuesOutsideTheMIDIRange() {
        XCTAssertNil(Velocity(-1))
        XCTAssertNil(Velocity(128))
    }

    func testVelocityValidRangeIsOneToOneTwentySeven() {
        XCTAssertEqual(Velocity.validRange, 1...127)
    }

    // MARK: - Sustain

    func testSustainAcceptsTheWholeValidRange() {
        for percent in 1...200 {
            XCTAssertEqual(Sustain(percent: percent)?.percent, percent)
        }
    }

    /// El 0% no es una nota corta: es una nota que no suena, y para eso está
    /// Probability.
    func testSustainRejectsZero() {
        XCTAssertNil(Sustain(percent: 0))
    }

    func testSustainRejectsValuesOutsideTheRange() {
        XCTAssertNil(Sustain(percent: -1))
        XCTAssertNil(Sustain(percent: 201))
    }

    /// El tope de 200% acota el solape a un solo vecino: una nota puede ligar
    /// sobre el Step siguiente pero nunca alcanzar el tercero. Ver la
    /// limitación 1 del spec.
    func testSustainValidRangeIsOneToTwoHundredPercent() {
        XCTAssertEqual(Sustain.validRange, 1...200)
    }

    // MARK: - Probability

    /// **Los dos extremos son válidos.** Probability 0% no emite nada y
    /// Probability 100% no omite nada; ninguno de los dos es un caso límite a
    /// rechazar, y el spec los declara estados válidos.
    func testProbabilityAcceptsTheWholeValidRangeIncludingBothExtremes() {
        for percent in 0...100 {
            XCTAssertEqual(Probability(percent: percent)?.percent, percent)
        }
    }

    func testProbabilityRejectsValuesOutsideTheRange() {
        XCTAssertNil(Probability(percent: -1))
        XCTAssertNil(Probability(percent: 101))
    }

    func testProbabilityValidRangeIsZeroToOneHundredPercent() {
        XCTAssertEqual(Probability.validRange, 0...100)
    }

    // MARK: - Defaults de producto

    /// Los defaults salen del spec y de la Pre Spec: Sustain default es «una
    /// Division completa», que es exactamente el 100%.
    func testProductDefaults() {
        XCTAssertEqual(Velocity.default.value, 100)
        XCTAssertEqual(Sustain.default.percent, 100)
        XCTAssertEqual(Probability.default.percent, 100)
    }
}
