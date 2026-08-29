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

/// Tests de `Groove` como valor y de su entrada en `Track`.
///
/// **La restricción dura de esta fase es la trivialidad.** `Track` se copia en
/// el hilo del scheduler y `tech-stack.md` lo exige POD; meter Groove dentro es
/// la primera vez desde el pool que se puede romper.
final class GrooveTests: XCTestCase {

    // MARK: - Trivialidad

    func testGrooveIsTrivial() {
        XCTAssertTrue(_isPOD(Groove.self), "Groove dejó de ser trivial")
        XCTAssertTrue(_isPOD(Velocity.self))
        XCTAssertTrue(_isPOD(Sustain.self))
        XCTAssertTrue(_isPOD(Probability.self))
    }

    func testTrackStaysTrivialWithGrooveInside() {
        XCTAssertTrue(_isPOD(Track.self), "Track dejó de ser trivial al entrar Groove")
    }

    // MARK: - Groove como valor

    func testGrooveDefaultCarriesTheProductDefaults() {
        let groove = Groove.default

        XCTAssertEqual(groove.velocity, .default)
        XCTAssertEqual(groove.sustain, .default)
        XCTAssertEqual(groove.probability, .default)
    }

    func testGrooveKeepsWhatItIsBuiltWith() {
        let groove = Groove(
            velocity: Velocity(64)!,
            sustain: Sustain(percent: 25)!,
            probability: Probability(percent: 50)!
        )

        XCTAssertEqual(groove.velocity.value, 64)
        XCTAssertEqual(groove.sustain.percent, 25)
        XCTAssertEqual(groove.probability.percent, 50)
    }

    // MARK: - Groove dentro de Track

    /// **Ningún llamante existente cambia.** `Track` se construye en muchos
    /// sitios que no saben nada de Groove; el default de producto es lo que les
    /// permite seguir compilando y sonando igual.
    func testTrackBuiltWithoutGrooveTakesTheProductDefault() {
        let track = Track(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!))

        XCTAssertEqual(track.groove, .default)
    }

    /// La regla de destructividad de `product-guidelines.md`: cambiar un
    /// parámetro nunca destruye material. Aquí se comprueba en la dirección que
    /// esta fase introduce — dar otro Groove no toca el Shape ni el pool.
    func testGivingATrackAnotherGrooveKeepsItsShapeAndPool() {
        var pool = PitchPool()
        pool = pool.toggling(Pitch(60)!)
        pool = pool.toggling(Pitch(64)!)
        let shape = Shape(steps: Steps(12)!, pulses: Pulses(7)!, rotate: Rotate(3))

        let track = Track(shape: shape, pool: pool)
        let louder = Track(
            shape: track.shape, pool: track.pool,
            groove: Groove(
                velocity: Velocity(127)!,
                sustain: .default,
                probability: .default
            ))

        XCTAssertEqual(louder.shape, shape)
        XCTAssertEqual(louder.pool, pool)
        XCTAssertEqual(louder.groove.velocity.value, 127)
    }
}

/// Tests del ajuste por delta de los tres parámetros de Groove.
///
/// **Los tres se frenan, ninguno envuelve.** Son escalas con principio y fin,
/// como `Steps` y `Division` y a diferencia de `Rotate`, que gira sobre un
/// anillo cerrado. `product-guidelines.md` pide que girar produzca «siempre un
/// cambio inmediato y proporcional»; envolver convertiría un ajuste fino contra
/// el extremo en un salto al otro lado del rango.
final class GrooveAdjustmentTests: XCTestCase {

    // MARK: - Velocity

    func testVelocityMovesByTheDelta() {
        XCTAssertEqual(Velocity(100)!.advanced(by: 1).value, 101)
        XCTAssertEqual(Velocity(100)!.advanced(by: -1).value, 99)
        XCTAssertEqual(Velocity(100)!.advanced(by: 20).value, 120)
    }

    func testVelocityStopsAtBothEnds() {
        XCTAssertEqual(Velocity(127)!.advanced(by: 1).value, 127)
        XCTAssertEqual(Velocity(1)!.advanced(by: -1).value, 1)
        XCTAssertEqual(Velocity(100)!.advanced(by: 1000).value, 127)
        XCTAssertEqual(Velocity(100)!.advanced(by: -1000).value, 1)
    }

    // MARK: - Sustain

    func testSustainMovesByTheDelta() {
        XCTAssertEqual(Sustain(percent: 100)!.advanced(by: 5).percent, 105)
        XCTAssertEqual(Sustain(percent: 100)!.advanced(by: -5).percent, 95)
    }

    func testSustainStopsAtBothEnds() {
        XCTAssertEqual(Sustain(percent: 200)!.advanced(by: 1).percent, 200)
        XCTAssertEqual(Sustain(percent: 1)!.advanced(by: -1).percent, 1)
        XCTAssertEqual(Sustain(percent: 100)!.advanced(by: 1000).percent, 200)
        XCTAssertEqual(Sustain(percent: 100)!.advanced(by: -1000).percent, 1)
    }

    // MARK: - Probability

    func testProbabilityMovesByTheDelta() {
        XCTAssertEqual(Probability(percent: 50)!.advanced(by: 10).percent, 60)
        XCTAssertEqual(Probability(percent: 50)!.advanced(by: -10).percent, 40)
    }

    /// El extremo inferior es el 0, no el 1: a diferencia de los otros dos,
    /// «no suena nada» es un estado que el knob tiene que poder alcanzar.
    func testProbabilityStopsAtBothEndsIncludingZero() {
        XCTAssertEqual(Probability(percent: 100)!.advanced(by: 1).percent, 100)
        XCTAssertEqual(Probability(percent: 0)!.advanced(by: -1).percent, 0)
        XCTAssertEqual(Probability(percent: 50)!.advanced(by: -1000).percent, 0)
        XCTAssertEqual(Probability(percent: 50)!.advanced(by: 1000).percent, 100)
    }

    // MARK: - Girar contra un extremo no mueve nada

    /// **Es lo que después permite no publicar.** `ControlInput` compara el
    /// valor ajustado con el vigente y solo publica si difieren; para que esa
    /// comparación signifique algo, girar contra un tope tiene que devolver
    /// exactamente el mismo valor.
    func testTurningAgainstAnEndReturnsTheSameValue() {
        XCTAssertEqual(Velocity(127)!.advanced(by: 5), Velocity(127)!)
        XCTAssertEqual(Sustain(percent: 1)!.advanced(by: -5), Sustain(percent: 1)!)
        XCTAssertEqual(Probability(percent: 0)!.advanced(by: -5), Probability(percent: 0)!)
    }

    /// Un delta de cero no es un caso especial que haya que interceptar antes:
    /// el propio ajuste devuelve el mismo valor.
    func testZeroDeltaChangesNothing() {
        XCTAssertEqual(Velocity(64)!.advanced(by: 0), Velocity(64)!)
        XCTAssertEqual(Sustain(percent: 64)!.advanced(by: 0), Sustain(percent: 64)!)
        XCTAssertEqual(Probability(percent: 64)!.advanced(by: 0), Probability(percent: 64)!)
    }
}
