import XCTest

@testable import Engine

/// Tests del offset de velocity y su acotado (FR6, FR7).
///
/// ```
/// offset = wave(p) · accent · 63 / 10000      // entero, wave ∈ −100…100
/// ```
///
/// **`accent = ±100` sobre el pico desplaza ±63 unidades MIDI**, media excursión
/// del rango. Con la Velocity en el centro, un accent al extremo barre casi
/// 1…127 sin recortar; con la Velocity por defecto —100— recorta arriba, y ver
/// ese recorte es justo lo que el panel de la pantalla sirve para enseñar.
///
/// **El acotado a 1…127 lo hace `Velocity.advanced(by:)`, que ya existe y ya
/// está cubierto.** La modulación lo reutiliza en vez de escribir un segundo
/// acotado: el extremo inferior sigue excluyendo el 0 porque un note-on con
/// velocity 0 es un note-off, y para no sonar está Probability.
///
/// **Con `accent = 0` el offset es 0 para las cuatro formas.** Es el criterio 1
/// de aceptación de la rebanada, y aquí es donde se prueba con números.
final class ModulationOffsetTests: XCTestCase {

    private let base = Velocity(100)!

    // MARK: - El neutro

    /// Con `accent = 0` no hay desviación en ningún Step de la vuelta, sea cual
    /// sea la forma. Es la no regresión de la rebanada entera.
    func testWithoutAccentThereIsNoOffsetForAnyWaveform() {
        for waveform in Waveform.allCases {
            let modulation = Modulation(waveform: waveform)
            for step in 0..<16 {
                XCTAssertEqual(
                    modulation.offset(atStep: step, of: 16), 0, "\(waveform) step \(step)")
            }
        }
    }

    /// Y la velocity emitida es la base, intacta, en los dieciséis.
    func testWithoutAccentEveryStepSoundsAtTheBaseVelocity() {
        for waveform in Waveform.allCases {
            let modulation = Modulation(waveform: waveform)
            for step in 0..<16 {
                XCTAssertEqual(
                    modulation.velocity(atStep: step, of: 16, from: base).value,
                    100,
                    "\(waveform) step \(step)"
                )
            }
        }
    }

    // MARK: - Los extremos

    /// **`accent = +100` sobre el pico da +63 unidades**, media excursión del
    /// rango MIDI (FR6).
    func testFullPositiveAccentMovesSixtyThreeUnitsAtThePeak() {
        let modulation = Modulation(waveform: .triangle, accent: Accent(percent: 100)!)
        XCTAssertEqual(modulation.offset(atStep: 4, of: 16), 63)
        XCTAssertEqual(modulation.offset(atStep: 12, of: 16), -63)
    }

    /// Y `accent = −100` lo mismo del otro lado: el signo invierte la onda, no
    /// la deforma.
    func testFullNegativeAccentMovesSixtyThreeUnitsTheOtherWay() {
        let modulation = Modulation(waveform: .triangle, accent: Accent(percent: -100)!)
        XCTAssertEqual(modulation.offset(atStep: 4, of: 16), -63)
        XCTAssertEqual(modulation.offset(atStep: 12, of: 16), 63)
    }

    /// Con la Velocity en el centro del rango, un accent al extremo barre
    /// prácticamente 1…127 sin recortar — que es lo que «media excursión»
    /// significa en la práctica.
    func testFromTheCentreOfTheRangeFullAccentSweepsAlmostEverything() {
        let centre = Velocity(64)!
        let modulation = Modulation(waveform: .triangle, accent: Accent(percent: 100)!)
        XCTAssertEqual(modulation.velocity(atStep: 4, of: 16, from: centre).value, 127)
        XCTAssertEqual(modulation.velocity(atStep: 12, of: 16, from: centre).value, 1)
    }

    // MARK: - La simetría del signo

    /// **`accent = −n` es el complemento exacto de `accent = +n`** respecto de
    /// la base, Step a Step y para las cuatro formas (criterio 4). Es lo que
    /// hace que el signo se lea como «al revés» y no como «otra cosa».
    ///
    /// La división entera trunca hacia cero, que es simétrica: si truncara hacia
    /// abajo, `+n` y `−n` se separarían una unidad en la mitad de los Steps.
    func testNegativeAccentIsTheExactComplementOfPositiveAccent() {
        for waveform in Waveform.allCases {
            for percent in [17, 50, 63, 100] {
                let up = Modulation(waveform: waveform, accent: Accent(percent: percent)!)
                let down = Modulation(waveform: waveform, accent: Accent(percent: -percent)!)
                for step in 0..<16 {
                    XCTAssertEqual(
                        up.offset(atStep: step, of: 16),
                        -down.offset(atStep: step, of: 16),
                        "\(waveform) accent \(percent) step \(step)"
                    )
                }
            }
        }
    }

    /// Sobre la velocity, la simetría vale **salvo donde el acotado muerde**
    /// (criterio 4): desde el centro del rango no muerde, y las dos se separan
    /// lo mismo de la base.
    func testTheComplementHoldsOnVelocityWhereTheClampDoesNotBite() {
        let centre = Velocity(64)!
        let up = Modulation(waveform: .sine, accent: Accent(percent: 40)!)
        let down = Modulation(waveform: .sine, accent: Accent(percent: -40)!)
        for step in 0..<16 {
            let above = up.velocity(atStep: step, of: 16, from: centre).value - 64
            let below = 64 - down.velocity(atStep: step, of: 16, from: centre).value
            XCTAssertEqual(above, below, "step \(step)")
        }
    }

    // MARK: - El acotado

    /// Con `Velocity = 127` y accent positivo, **nada supera 127** (criterio 5).
    func testNothingExceedsTheTopFromTheTopVelocity() {
        let top = Velocity(127)!
        for waveform in Waveform.allCases {
            let modulation = Modulation(waveform: waveform, accent: Accent(percent: 100)!)
            for step in 0..<16 {
                XCTAssertLessThanOrEqual(
                    modulation.velocity(atStep: step, of: 16, from: top).value,
                    127,
                    "\(waveform) step \(step)"
                )
            }
        }
    }

    /// Con `Velocity = 1` y accent negativo, **nada baja de 1** (criterio 5).
    /// El 0 queda fuera porque un note-on con velocity 0 es un note-off.
    func testNothingFallsBelowOneFromTheBottomVelocity() {
        let bottom = Velocity(1)!
        for waveform in Waveform.allCases {
            let modulation = Modulation(waveform: waveform, accent: Accent(percent: -100)!)
            for step in 0..<16 {
                XCTAssertGreaterThanOrEqual(
                    modulation.velocity(atStep: step, of: 16, from: bottom).value,
                    1,
                    "\(waveform) step \(step)"
                )
            }
        }
    }

    /// La barrida completa: ninguna combinación de forma, accent, base y
    /// longitud de vuelta se sale de 1…127.
    func testTheEmittedVelocityNeverLeavesTheMidiRange() {
        for waveform in Waveform.allCases {
            for percent in [-100, -37, 0, 37, 100] {
                let modulation = Modulation(waveform: waveform, accent: Accent(percent: percent)!)
                for baseValue in [1, 64, 100, 127] {
                    let from = Velocity(baseValue)!
                    for stepCount in [1, 9, 16] {
                        for step in 0..<stepCount {
                            let value = modulation.velocity(
                                atStep: step, of: stepCount, from: from
                            ).value
                            XCTAssertTrue(
                                Velocity.validRange.contains(value),
                                "\(waveform)/\(percent)/\(baseValue)/\(stepCount)/\(step) dio \(value)"
                            )
                        }
                    }
                }
            }
        }
    }

    /// El recorte que la spec anota como limitación: con la Velocity por defecto
    /// —100— y accent alto, media onda se aplasta contra 127. Se ve en el panel
    /// y no se avisa de otra forma.
    func testTheDefaultVelocityClipsAgainstTheTopWithHighAccent() {
        let modulation = Modulation(waveform: .triangle, accent: Accent(percent: 100)!)
        XCTAssertEqual(modulation.velocity(atStep: 4, of: 16, from: base).value, 127)
        XCTAssertEqual(modulation.velocity(atStep: 3, of: 16, from: base).value, 127)
        // Y abajo no recorta: 100 − 63 = 37, con margen de sobra.
        XCTAssertEqual(modulation.velocity(atStep: 12, of: 16, from: base).value, 37)
    }

    // MARK: - El redondeo

    /// **La aritmética es entera y trunca hacia cero.** Fijado en los valores
    /// que caen a mitad de unidad: `triangle` en el Step 2 de 16 vale 50, y
    /// `50 · 100 · 63 / 10000` es 31,5 exacto — sale 31, y su simétrico −31.
    func testTheHalfUnitRoundingTruncatesTowardsZero() {
        let up = Modulation(waveform: .triangle, accent: Accent(percent: 100)!)
        let down = Modulation(waveform: .triangle, accent: Accent(percent: -100)!)
        XCTAssertEqual(Waveform.triangle.value(atStep: 2, of: 16), 50)
        XCTAssertEqual(up.offset(atStep: 2, of: 16), 31)
        XCTAssertEqual(down.offset(atStep: 2, of: 16), -31)
    }

    /// Un accent pequeño sobre una onda pequeña se queda en 0 y no en 1: la
    /// modulación no inventa una unidad que la aritmética no da.
    func testASmallAccentOnASmallExcursionRoundsAwayToNothing() {
        let modulation = Modulation(waveform: .triangle, accent: Accent(percent: 1)!)
        XCTAssertEqual(modulation.offset(atStep: 1, of: 16), 0)
        XCTAssertEqual(modulation.offset(atStep: 4, of: 16), 0)
    }

    // MARK: - El Groove modulado

    /// **Solo toca la velocity.** Sustain, Probability, Timing y Delay salen
    /// intactos: la modulación cambia con cuánta fuerza suena un Step, no cuándo
    /// suena ni cuánto dura. Es lo que sostiene NFR3.
    func testTheModulatedGrooveOnlyChangesTheVelocity() {
        let groove = Groove(
            velocity: Velocity(64)!,
            sustain: Sustain(percent: 150)!,
            probability: Probability(percent: 40)!,
            timing: Timing(percent: 66)!,
            delay: Delay(percent: -30)!
        )
        let modulation = Modulation(waveform: .triangle, accent: Accent(percent: 100)!)
        let voiced = groove.modulated(by: modulation, atStep: 4, of: 16)

        XCTAssertEqual(voiced.velocity.value, 127)
        XCTAssertEqual(voiced.sustain, groove.sustain)
        XCTAssertEqual(voiced.probability, groove.probability)
        XCTAssertEqual(voiced.timing, groove.timing)
        XCTAssertEqual(voiced.delay, groove.delay)
    }

    /// **Con `accent` en 0 devuelve el mismo Groove**, sin construir nada. Es el
    /// criterio 1, y hace que el camino nuevo no cueste nada a quien no lo pide.
    func testAGrooveWithoutAccentComesBackUntouched() {
        let groove = Groove(velocity: base, sustain: .default, probability: .default)
        for waveform in Waveform.allCases {
            for step in 0..<16 {
                XCTAssertEqual(
                    groove.modulated(by: Modulation(waveform: waveform), atStep: step, of: 16),
                    groove,
                    "\(waveform) step \(step)"
                )
            }
        }
    }

    /// La serie de velocities finales de una vuelta, con recorte incluido. Es el
    /// dato que el panel `velocity response` dibuja (FR12), y por eso se prueba
    /// aquí con números y no mirándolo.
    func testTheWholeTurnOfFinalVelocities() {
        let groove = Groove(velocity: base, sustain: .default, probability: .default)
        let modulation = Modulation(waveform: .triangle, accent: Accent(percent: 100)!)
        let turn = (0..<16).map {
            groove.modulated(by: modulation, atStep: $0, of: 16).velocity.value
        }
        XCTAssertEqual(
            turn,
            [100, 115, 127, 127, 127, 127, 127, 115, 100, 85, 69, 53, 37, 53, 69, 85]
        )
    }

    /// Y sobre un anillo de nueve, que es el caso que el panel tiene que dibujar
    /// con nueve barras y no con dieciséis (FR13).
    func testTheWholeTurnOfANineStepRing() {
        let groove = Groove(velocity: Velocity(64)!, sustain: .default, probability: .default)
        let modulation = Modulation(waveform: .triangle, accent: Accent(percent: 100)!)
        let turn = (0..<9).map {
            groove.modulated(by: modulation, atStep: $0, of: 9).velocity.value
        }
        XCTAssertEqual(turn.count, 9)
        XCTAssertEqual(turn[0], 64)
        XCTAssertEqual(turn, [64, 91, 119, 106, 78, 51, 23, 8, 36])
    }

    // MARK: - La vuelta que el panel dibuja

    /// **Tantas entradas como Steps**, no dieciséis (FR13): el panel es el
    /// espejo del anillo.
    func testTheResponseHasOneEntryPerStep() {
        for stepCount in [1, 9, 16] {
            let cycle = Cycle(shape: Shape(steps: Steps(stepCount)!, pulses: Pulses(1)!))
            XCTAssertEqual(cycle.velocityResponse.count, stepCount, "\(stepCount) Steps")
        }
    }

    /// **La altura es la velocity final, recorte incluido** (FR12). Con la
    /// Velocity por defecto y accent al extremo, media onda se aplasta contra
    /// 127 — y eso es justo lo que el panel existe para enseñar.
    func testTheResponseCarriesTheFinalVelocityWithItsClipping() {
        let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!))
            .with(modulation: Modulation(waveform: .triangle, accent: Accent(percent: 100)!))

        XCTAssertEqual(
            cycle.velocityResponse.map(\.velocity.value),
            [100, 115, 127, 127, 127, 127, 127, 115, 100, 85, 69, 53, 37, 53, 69, 85]
        )
    }

    /// **Y dice cuáles disparan** (FR13), para dibujar atenuados los que no. El
    /// LFO corre sobre ellos igualmente (FR8): tienen valor y no suenan.
    func testTheResponseSaysWhichStepsTrigger() {
        let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!))
        let response = cycle.velocityResponse

        XCTAssertEqual(response.map(\.triggers).filter { $0 }.count, 4)
        for (step, entry) in response.enumerated() {
            XCTAssertEqual(entry.triggers, cycle.triggers(atStep: step), "step \(step)")
        }
    }

    /// Los Steps que no disparan **también llevan su velocity**: es lo que hace
    /// que el panel enseñe la onda completa y no solo cuatro barras sueltas.
    func testTheStepsThatDoNotTriggerStillCarryTheirVelocity() {
        let cycle = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!),
            groove: Groove(velocity: Velocity(64)!, sustain: .default, probability: .default)
        )
        .with(modulation: Modulation(waveform: .triangle, accent: Accent(percent: 100)!))

        let response = cycle.velocityResponse
        XCTAssertEqual(response[4].velocity.value, 127)
        XCTAssertEqual(response[12].velocity.value, 1)
        XCTAssertTrue(response.contains { !$0.triggers })
    }

    /// Con `accent` en 0 todas las barras miden la Velocity del Cycle: el panel
    /// enseña una línea recta, que es lo que suena.
    func testWithoutAccentTheResponseIsFlat() {
        let cycle = Cycle(
            shape: Shape(steps: Steps(9)!, pulses: Pulses(9)!),
            groove: Groove(velocity: Velocity(90)!, sustain: .default, probability: .default)
        )
        XCTAssertEqual(
            cycle.velocityResponse.map(\.velocity.value), Array(repeating: 90, count: 9))
    }

    // MARK: - El valor

    /// Los defaults del producto: sin modulación, sobre `triangle`.
    func testModulationDefaultsToTriangleWithoutAccent() {
        XCTAssertEqual(Modulation.default.waveform, .triangle)
        XCTAssertEqual(Modulation.default.accent, .default)
    }

    /// El mismo `Modulation` con lo que se le cambie y todo lo demás intacto —
    /// mismo idioma que `Cycle.with(...)` y `NoteRepeater.with(...)`.
    func testWithChangesOnlyWhatItIsGiven() {
        let modulation = Modulation(waveform: .pulse, accent: Accent(percent: 40)!)
        XCTAssertEqual(modulation.with(waveform: .sine).waveform, .sine)
        XCTAssertEqual(modulation.with(waveform: .sine).accent.percent, 40)
        XCTAssertEqual(modulation.with(accent: Accent(percent: -5)!).waveform, .pulse)
        XCTAssertEqual(modulation.with(accent: Accent(percent: -5)!).accent.percent, -5)
    }

    /// La igualdad distingue dos modulaciones que solo difieren en la onda.
    func testEqualityDistinguishesTheWaveform() {
        XCTAssertNotEqual(Modulation(waveform: .saw), Modulation(waveform: .sine))
        XCTAssertEqual(Modulation(waveform: .saw), Modulation(waveform: .saw))
    }
}
