import XCTest

@testable import Engine

/// Tests de los dos tipos de la modulación: `Waveform` y `Accent`.
///
/// **`Accent` valida en el inicializador**, como `Velocity`, `Sustain` y `Ramp`:
/// un valor que existe es siempre aplicable, y ningún sitio de uso vuelve a
/// comprobar el rango.
///
/// **No envuelve.** Es el criterio de `Velocity` y `Sustain` y no el de
/// `Rotate`: pasarse de un extremo devuelve el extremo, porque saltar de +100 a
/// −100 convierte un ajuste fino en el cambio más brutal que el parámetro
/// admite. Aquí importa más que en los knobs, porque quien lo mueve es un dedo
/// arrastrando y no un encoder por clics.
///
/// **El 0 está dentro del rango y es el default**, y de él depende toda la no
/// regresión de la rebanada (criterio 1): con `accent = 0` la salida es la de
/// antes. No es un extremo incómodo — es el valor que apaga la modulación.
final class ModulationTypesTests: XCTestCase {

    // MARK: - Waveform

    /// Cuatro casos y ninguno más, tal y como los lista la Pre Spec.
    func testWaveformHasExactlyFourCases() {
        XCTAssertEqual(Waveform.allCases.count, 4)
        XCTAssertEqual(Waveform.allCases, [.saw, .triangle, .sine, .pulse])
    }

    /// El default del producto. `triangle` es la forma que sube y baja
    /// simétricamente, que es la lectura menos sorprendente de «modulación».
    func testWaveformDefaultsToTriangle() {
        XCTAssertEqual(Waveform.default, .triangle)
    }

    /// **La lectura es el mismo término en minúscula** (FR2, FR20): ni «LFO»,
    /// ni «shape», ni un sinónimo nuevo (NFR7).
    func testWaveformReadsAsItsOwnTermInLowercase() {
        XCTAssertEqual(Waveform.saw.description, "saw")
        XCTAssertEqual(Waveform.triangle.description, "triangle")
        XCTAssertEqual(Waveform.sine.description, "sine")
        XCTAssertEqual(Waveform.pulse.description, "pulse")
    }

    /// El recorrido de la rejilla 2×2 de la pantalla es el de `allCases`, así
    /// que su orden es parte del contrato y no un detalle del compilador.
    func testWaveformKeepsTheOrderTheScreenDraws() {
        XCTAssertEqual(
            Waveform.allCases.map(\.description),
            ["saw", "triangle", "sine", "pulse"]
        )
    }

    // MARK: - Accent

    /// El default es 0, y de él depende la no regresión de la rebanada
    /// (criterio 1).
    func testAccentDefaultsToZero() {
        XCTAssertEqual(Accent.default.percent, 0)
    }

    /// **Bipolar y simétrico**, como `Delay`, `Ramp` y `Pace`.
    func testAccentAcceptsItsWholeRange() {
        for percent in [-100, -63, -1, 0, 1, 63, 100] {
            XCTAssertEqual(Accent(percent: percent)?.percent, percent, "accent \(percent)")
        }
    }

    /// El `init?` devuelve `nil` fuera de rango, que es lo que hace que un
    /// `Accent` que existe sea siempre aplicable.
    func testAccentRejectsValuesOutsideItsRange() {
        XCTAssertNil(Accent(percent: -101))
        XCTAssertNil(Accent(percent: 101))
    }

    /// **El 0 está dentro del rango.** No es un extremo: es el valor que apaga
    /// la modulación, y por eso el rango lo cruza como `Delay` cruza el suyo.
    func testAccentIncludesZeroInItsRange() {
        XCTAssertNotNil(Accent(percent: 0))
        XCTAssertTrue(Accent.validRange.contains(0))
    }

    func testAccentMovesByTheDragDelta() {
        XCTAssertEqual(Accent(percent: 20)!.advanced(by: 15).percent, 35)
        XCTAssertEqual(Accent(percent: 20)!.advanced(by: -50).percent, -30)
    }

    /// **Se detiene en los extremos, no envuelve.** Ver `Velocity` y `Sustain`.
    func testAccentStopsAtBothEnds() {
        XCTAssertEqual(Accent(percent: 100)!.advanced(by: 1).percent, 100)
        XCTAssertEqual(Accent(percent: -100)!.advanced(by: -1).percent, -100)
        XCTAssertEqual(Accent(percent: -100)!.advanced(by: 500).percent, 100)
        XCTAssertEqual(Accent(percent: 100)!.advanced(by: -500).percent, -100)
    }

    /// El cero no es un punto de parada del arrastre: se cruza como cualquier
    /// otro valor. El imantado del slider (FR18) es de la vista, no del tipo.
    func testAccentCrossesZeroWithoutCatchingOnIt() {
        XCTAssertEqual(Accent(percent: 5)!.advanced(by: -10).percent, -5)
        XCTAssertEqual(Accent(percent: -5)!.advanced(by: 10).percent, 5)
    }

    // MARK: - Cómo se lee

    /// **El signo se ve también en el positivo**, que es la convención que
    /// `Rotate` y `Delay` ya siguen para los parámetros bipolares: sin él, `34`
    /// sería ambiguo entre «sube 34» y «el valor es 34».
    func testAPositiveAccentShowsItsSign() {
        XCTAssertEqual(Accent(percent: 34)!.description, "+34")
        XCTAssertEqual(Accent(percent: 100)!.description, "+100")
        XCTAssertEqual(Accent(percent: 1)!.description, "+1")
    }

    /// El negativo lo lleva por la interpolación, como el resto del motor.
    func testANegativeAccentShowsItsSign() {
        XCTAssertEqual(Accent(percent: -12)!.description, "-12")
        XCTAssertEqual(Accent(percent: -100)!.description, "-100")
    }

    /// **El 0 va sin signo.** No es un valor pequeño hacia ningún lado: es el
    /// que apaga la modulación, y escribirlo `+0` le inventaría una dirección.
    func testZeroGoesWithoutASign() {
        XCTAssertEqual(Accent.default.description, "0")
        XCTAssertEqual(Accent(percent: 0)!.description, "0")
    }

    /// Vive en `Engine` y no en la vista (NFR6): un formato es exactamente lo que
    /// `workflow.md` dice que no debe estar donde no hay tests.
    func testEveryValueOfTheRangeReadsBack() {
        for percent in Accent.validRange {
            let text = Accent(percent: percent)!.description
            XCTAssertEqual(Int(text.replacingOccurrences(of: "+", with: "")), percent)
        }
    }
}
