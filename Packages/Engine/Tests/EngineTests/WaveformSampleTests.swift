import XCTest

@testable import Engine

/// Tests de la onda muestreada por Step — el núcleo de la modulación (FR4, FR5).
///
/// **La fase sale del índice de Step dentro de la vuelta**, `p = s / stepCount`,
/// y de ahí que un ciclo de modulación dure exactamente una vuelta del anillo
/// sin que nadie tenga que sincronizar nada. No hay reloj de modulación ni
/// estado que mantener.
///
/// **Las cuatro formas valen 0 en el Step 0 y crecen desde ahí**, así que el
/// primer Step de cada vuelta suena a la Velocity base y la desviación es lo que
/// se desarrolla. `pulse` es la excepción y no puede no serlo: una onda de dos
/// valores no pasa por el centro, y empieza **arriba**, que es la lectura que
/// hace la forma útil para lo que sirve — acentuar media vuelta entera.
///
/// **Las cuatro tienen el pico en el cuarto de vuelta.** Es lo que hace que
/// cambiar de forma no mueva el acento de sitio, solo su recorrido; de ahí que
/// `saw` corte en `p=¼` en vez de a media vuelta.
///
/// Aritmética entera de principio a fin: esto corre en el hilo del scheduler
/// (NFR1), y `sine` se resuelve por tabla escrita y no con `sin()` (NFR5).
final class WaveformSampleTests: XCTestCase {

    // MARK: - El centro de partida

    /// Las cuatro valen 0 en el Step 0 —salvo `pulse`, que vale +100— sea cual
    /// sea la longitud de la vuelta (FR5).
    func testEveryWaveformStartsAtTheCentreExceptPulse() {
        for stepCount in [1, 9, 16] {
            XCTAssertEqual(Waveform.saw.value(atStep: 0, of: stepCount), 0, "saw \(stepCount)")
            XCTAssertEqual(
                Waveform.triangle.value(atStep: 0, of: stepCount), 0, "triangle \(stepCount)")
            XCTAssertEqual(Waveform.sine.value(atStep: 0, of: stepCount), 0, "sine \(stepCount)")
            XCTAssertEqual(
                Waveform.pulse.value(atStep: 0, of: stepCount), 100, "pulse \(stepCount)")
        }
    }

    /// Con un solo Step la fase es siempre 0 y no se divide por cero: la vuelta
    /// entera es un Step, así que la modulación no tiene recorrido.
    func testASingleStepIsAlwaysPhaseZero() {
        for waveform in Waveform.allCases {
            let expected = waveform == .pulse ? 100 : 0
            XCTAssertEqual(waveform.value(atStep: 0, of: 1), expected, "\(waveform)")
        }
    }

    /// Un `stepCount` no positivo no puede ocurrir —`Steps` valida 1…64— pero la
    /// función corre en el hilo del scheduler y ahí una división por cero es un
    /// crash, no un valor raro. Devuelve el centro.
    func testANonPositiveStepCountIsTheCentreAndNotACrash() {
        for waveform in Waveform.allCases {
            XCTAssertEqual(waveform.value(atStep: 0, of: 0), 0, "\(waveform)")
            XCTAssertEqual(waveform.value(atStep: 3, of: -4), 0, "\(waveform)")
        }
    }

    /// **El índice envuelve sobre la vuelta**, como `Cycle.triggers(atStep:)`:
    /// el Step 16 de una vuelta de 16 es el Step 0 de la siguiente, y eso es
    /// exactamente lo que hace que el ciclo dure una vuelta.
    func testTheStepIndexWrapsAroundTheTurn() {
        for waveform in Waveform.allCases {
            for step in 0..<16 {
                XCTAssertEqual(
                    waveform.value(atStep: step + 16, of: 16),
                    waveform.value(atStep: step, of: 16),
                    "\(waveform) step \(step)"
                )
                XCTAssertEqual(
                    waveform.value(atStep: step - 16, of: 16),
                    waveform.value(atStep: step, of: 16),
                    "\(waveform) step \(step) hacia atrás"
                )
            }
        }
    }

    // MARK: - triangle

    /// Sube al pico en el cuarto de vuelta, vuelve a 0 a media vuelta y baja al
    /// fondo en los tres cuartos. Caso literal de 16 Steps.
    func testTriangleRisesAndFallsSymmetrically() {
        XCTAssertEqual(
            Self.turn(of: .triangle, steps: 16),
            [0, 25, 50, 75, 100, 75, 50, 25, 0, -25, -50, -75, -100, -75, -50, -25]
        )
    }

    /// Los cuartos de vuelta, dichos aparte del array para que el requisito se
    /// lea sin contar posiciones (FR5).
    func testTriangleHitsItsQuartersExactly() {
        XCTAssertEqual(Waveform.triangle.value(atStep: 0, of: 16), 0)
        XCTAssertEqual(Waveform.triangle.value(atStep: 4, of: 16), 100)
        XCTAssertEqual(Waveform.triangle.value(atStep: 8, of: 16), 0)
        XCTAssertEqual(Waveform.triangle.value(atStep: 12, of: 16), -100)
    }

    /// **La segunda mitad es el espejo de la primera**, cambiada de signo: es lo
    /// que «subida y bajada simétricas» significa, y lo que hace que `accent`
    /// negativo sea la misma onda leída del otro lado.
    func testTriangleIsTheMirrorOfItselfInTheSecondHalf() {
        for step in 0..<8 {
            XCTAssertEqual(
                Waveform.triangle.value(atStep: step + 8, of: 16),
                -Waveform.triangle.value(atStep: step, of: 16),
                "step \(step)"
            )
        }
    }

    // MARK: - saw

    /// **Sube hasta el cuarto de vuelta, salta al fondo y vuelve a subir.** El
    /// corte cae en `p=¼` y no a media vuelta, que es lo que alinea su pico con
    /// el de las otras tres.
    func testSawRisesToTheQuarterTurnAndThenJumpsToTheBottom() {
        XCTAssertEqual(
            Self.turn(of: .saw, steps: 16),
            [0, 25, 50, 75, 100, -92, -84, -75, -67, -59, -50, -42, -34, -25, -17, -9]
        )
    }

    /// El salto está donde dice el spec: entre el Step del pico y el siguiente,
    /// y son casi las doscientas unidades de la excursión completa.
    func testSawJumpsExactlyAfterTheQuarterTurn() {
        let peak = Waveform.saw.value(atStep: 4, of: 16)
        let afterTheJump = Waveform.saw.value(atStep: 5, of: 16)
        XCTAssertEqual(peak, 100)
        XCTAssertLessThan(afterTheJump, -90)
        XCTAssertLessThan(afterTheJump - peak, -190)
    }

    /// Después del corte vuelve a subir, sin más saltos hasta cerrar la vuelta.
    func testSawRisesMonotonicallyAfterTheJump() {
        for step in 5..<15 {
            XCTAssertLessThan(
                Waveform.saw.value(atStep: step, of: 16),
                Waveform.saw.value(atStep: step + 1, of: 16),
                "step \(step)"
            )
        }
    }

    /// Y sube sin saltos hasta el pico, que es la otra mitad de «rampa
    /// ascendente con un corte»: un solo corte, no dos.
    func testSawRisesMonotonicallyUpToThePeak() {
        for step in 0..<4 {
            XCTAssertLessThan(
                Waveform.saw.value(atStep: step, of: 16),
                Waveform.saw.value(atStep: step + 1, of: 16),
                "step \(step)"
            )
        }
    }

    // MARK: - pulse

    /// **Exactamente dos valores en una vuelta**, y ninguno entre ellos.
    func testPulseProducesExactlyTwoValues() {
        for stepCount in [9, 16] {
            XCTAssertEqual(Set(Self.turn(of: .pulse, steps: stepCount)), [100, -100], "\(stepCount)")
        }
    }

    /// El cambio cae a media vuelta.
    func testPulseChangesAtHalfTurn() {
        XCTAssertEqual(
            Self.turn(of: .pulse, steps: 16),
            Array(repeating: 100, count: 8) + Array(repeating: -100, count: 8)
        )
    }

    /// **Con Steps impares la mitad se resuelve por la misma regla**, sin caso
    /// especial: un Step está arriba mientras su fase no ha llegado a la media
    /// vuelta, así que el Step del medio cae **en la mitad alta** y `pulse`
    /// acentúa `ceil(steps/2)` Steps de `steps`.
    func testPulseWithOddStepsPutsTheMiddleStepInTheHighHalf() {
        XCTAssertEqual(
            Self.turn(of: .pulse, steps: 9),
            [100, 100, 100, 100, 100, -100, -100, -100, -100]
        )
        XCTAssertEqual(Self.turn(of: .pulse, steps: 7), [100, 100, 100, 100, -100, -100, -100])
    }

    // MARK: - sine

    /// La misma forma que `triangle`, redondeada por la tabla. Caso literal de
    /// 16 Steps.
    func testSineIsTheRoundedShape() {
        XCTAssertEqual(
            Self.turn(of: .sine, steps: 16),
            [0, 38, 71, 92, 100, 92, 71, 38, 0, -38, -71, -92, -100, -92, -71, -38]
        )
    }

    /// **Su pico no se desvía del de `triangle`**: la tabla aproxima la forma,
    /// no otra cosa. Es lo que hace que cambiar de forma no mueva el acento de
    /// sitio.
    func testSinePeaksWhereTriangleDoes() {
        XCTAssertEqual(Waveform.sine.value(atStep: 4, of: 16), 100)
        XCTAssertEqual(Waveform.sine.value(atStep: 12, of: 16), -100)
        XCTAssertEqual(Waveform.sine.value(atStep: 0, of: 16), 0)
        XCTAssertEqual(Waveform.sine.value(atStep: 8, of: 16), 0)
    }

    /// Sube sin bajar hasta el pico y baja sin subir hasta el fondo — la tabla
    /// no puede introducir un rizo que la onda no tiene.
    func testSineIsMonotonicWhereItShouldBe() {
        for step in 0..<16 {
            XCTAssertLessThanOrEqual(
                Waveform.sine.value(atStep: step, of: 64),
                Waveform.sine.value(atStep: step + 1, of: 64),
                "subiendo, step \(step)"
            )
        }
        for step in 16..<48 {
            XCTAssertGreaterThanOrEqual(
                Waveform.sine.value(atStep: step, of: 64),
                Waveform.sine.value(atStep: step + 1, of: 64),
                "bajando, step \(step)"
            )
        }
    }

    /// La segunda mitad es el espejo de la primera, como en `triangle`.
    func testSineIsTheMirrorOfItselfInTheSecondHalf() {
        for step in 0..<32 {
            XCTAssertEqual(
                Waveform.sine.value(atStep: step + 32, of: 64),
                -Waveform.sine.value(atStep: step, of: 64),
                "step \(step)"
            )
        }
    }

    // MARK: - El rango, para las cuatro

    /// Ninguna forma sale de −100…100 en ninguna longitud de vuelta que `Steps`
    /// admita. Es la invariante de la que depende el acotado del offset (FR6).
    func testNoWaveformEverLeavesItsRange() {
        for waveform in Waveform.allCases {
            for stepCount in 1...64 {
                for step in 0..<stepCount {
                    let value = waveform.value(atStep: step, of: stepCount)
                    XCTAssertTrue(
                        (-100...100).contains(value),
                        "\(waveform) \(stepCount)/\(step) dio \(value)"
                    )
                }
            }
        }
    }

    // MARK: - Ayuda

    /// Una vuelta entera de la onda, Step a Step.
    private static func turn(of waveform: Waveform, steps: Int) -> [Int] {
        (0..<steps).map { waveform.value(atStep: $0, of: steps) }
    }
}
