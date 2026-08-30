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

    // MARK: - Timing

    func testTimingAcceptsTheWholeValidRange() {
        for percent in 50...75 {
            XCTAssertEqual(Timing(percent: percent)?.percent, percent)
        }
    }

    /// **Por debajo del 50% no hay swing, hay swing invertido.** El porcentaje
    /// es la posición del segundo Step del par dentro del par, así que un valor
    /// menor que 50 adelantaría el Step impar en lugar de atrasarlo. Para
    /// adelantar está Delay, que lo hace sobre el Track entero y con el
    /// presupuesto que eso exige.
    func testTimingRejectsValuesBelowStraight() {
        XCTAssertNil(Timing(percent: 49))
        XCTAssertNil(Timing(percent: 0))
        XCTAssertNil(Timing(percent: -1))
    }

    /// **El tope de 75% es corrección, no gusto.** Es medio Step de retraso: un
    /// Step desplazado llega justo antes del siguiente y nunca lo alcanza. Por
    /// encima, la secuencia de emisión podría invertirse, que es una nota fuera
    /// de sitio y no un valor extremo. Ver la invariante de orden del spec (FR3).
    func testTimingRejectsValuesAboveTheOrderPreservingLimit() {
        XCTAssertNil(Timing(percent: 76))
        XCTAssertNil(Timing(percent: 100))
    }

    func testTimingValidRangeIsFiftyToSeventyFivePercent() {
        XCTAssertEqual(Timing.validRange, 50...75)
    }

    /// El 50% no es un caso límite: es la rejilla recta, el punto de partida
    /// desde el que el knob se aparta.
    func testTimingAtFiftyPercentIsTheStraightGrid() {
        XCTAssertEqual(Timing.default.percent, 50)
        XCTAssertEqual(Timing.straight, Timing.default)
    }

    // MARK: - Delay

    /// **El único parámetro del motor con rango negativo.** Adelantar es tan
    /// válido como atrasar, y el cero no es un extremo sino el centro.
    func testDelayAcceptsTheWholeValidRangeIncludingNegatives() {
        for percent in -100...100 {
            XCTAssertEqual(Delay(percent: percent)?.percent, percent)
        }
    }

    func testDelayRejectsValuesOutsideTheRange() {
        XCTAssertNil(Delay(percent: -101))
        XCTAssertNil(Delay(percent: 101))
    }

    func testDelayValidRangeIsMinusOneHundredToOneHundredPercent() {
        XCTAssertEqual(Delay.validRange, -100...100)
    }

    func testDelayDefaultIsOnTheGrid() {
        XCTAssertEqual(Delay.default.percent, 0)
    }

    // MARK: - Defaults de producto

    /// Los defaults salen del spec y de la Pre Spec: Sustain default es «una
    /// Division completa», que es exactamente el 100%.
    func testProductDefaults() {
        XCTAssertEqual(Velocity.default.value, 100)
        XCTAssertEqual(Sustain.default.percent, 100)
        XCTAssertEqual(Probability.default.percent, 100)
    }

    /// **Los dos que llegan con la rebanada 6 no interpretan nada por defecto.**
    /// Timing 50% es la rejilla recta y Delay 0% no desplaza: el Groove default
    /// sigue siendo el que deja los instantes exactamente donde los pone
    /// `MusicalTimeline`, que es lo que permite que la medición de regresión no
    /// cambie de forma.
    func testTemporalProductDefaultsLeaveTheGridUntouched() {
        XCTAssertEqual(Timing.default.percent, 50)
        XCTAssertEqual(Delay.default.percent, 0)
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
        XCTAssertTrue(_isPOD(Timing.self))
        XCTAssertTrue(_isPOD(Delay.self))
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
        XCTAssertEqual(groove.timing, .default)
        XCTAssertEqual(groove.delay, .default)
    }

    /// **El Groove default sigue sin interpretar nada, ahora también en el
    /// tiempo.** Es lo que hace que la rejilla recta siga siendo la de
    /// `MusicalTimeline` y que el arnés de medición —que usa este valor— mida lo
    /// mismo que medía antes de la rebanada 6.
    func testTheDefaultGrooveLeavesTheGridStraight() {
        XCTAssertEqual(Groove.default.timing, .straight)
        XCTAssertEqual(Groove.default.delay.percent, 0)
    }

    /// **Ningún llamante existente cambia.** `Groove` se construye en tests y en
    /// código que no sabe nada de Timing ni de Delay; los defaults son lo que
    /// les permite seguir compilando y sonando igual.
    func testGrooveBuiltWithoutTheTemporalParametersTakesTheirDefaults() {
        let groove = Groove(
            velocity: Velocity(64)!,
            sustain: Sustain(percent: 25)!,
            probability: Probability(percent: 50)!
        )

        XCTAssertEqual(groove.timing, .default)
        XCTAssertEqual(groove.delay, .default)
        XCTAssertEqual(groove.velocity.value, 64)
    }

    func testGrooveKeepsTheTemporalParametersItIsBuiltWith() {
        let groove = Groove(
            velocity: .default,
            sustain: .default,
            probability: .default,
            timing: Timing(percent: 75)!,
            delay: Delay(percent: -100)!
        )

        XCTAssertEqual(groove.timing.percent, 75)
        XCTAssertEqual(groove.delay.percent, -100)
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

/// Tests del Step más corto que el producto puede producir, ahora que existe.
///
/// Hasta la rebanada 5 la lista de Divisions se cortaba en 1/16, y su
/// documentación decía por qué: a 300 BPM un Step de 1/32 dura 25 ms, que era
/// exactamente el gate constante, así que las notas se habrían solapado. Con
/// Sustain el gate ya no es constante y la condición se cumple.
final class ShortestStepTests: XCTestCase {

    /// **El caso que bloqueaba 1/32.** A 300 BPM el Step dura 25 ms; con Sustain
    /// 100% el gate dura exactamente eso, así que el note-off cae justo en el
    /// note-on del siguiente y no antes. El solape empieza **por encima** del
    /// 100%, que es donde el usuario lo pide.
    func testAtTheFastestDivisionAndHighestTempoFullSustainFillsTheStepExactly() throws {
        let timeline = MusicalTimeline(
            tempo: try XCTUnwrap(Tempo(beatsPerMinute: Tempo.validRange.upperBound)),
            division: try XCTUnwrap(Division.fastest)
        )
        let step = Int64(timeline.stepDurationNanoseconds)

        XCTAssertEqual(Sustain(percent: 100)!.gateNanoseconds(forStep: step), step)
        XCTAssertLessThan(Sustain(percent: 99)!.gateNanoseconds(forStep: step), step)
        XCTAssertGreaterThan(Sustain(percent: 101)!.gateNanoseconds(forStep: step), step)
    }

    func testTheShortestStepIsTwentyFiveMilliseconds() throws {
        let timeline = MusicalTimeline(
            tempo: try XCTUnwrap(Tempo(beatsPerMinute: 300)),
            division: try XCTUnwrap(Division.fastest)
        )
        XCTAssertEqual(timeline.stepDurationNanoseconds, 25_000_000, accuracy: 1.0)
    }
}
