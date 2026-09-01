import XCTest

@testable import Engine

/// Tests del tipo que nombra todo lo ajustable de un Track.
///
/// **Sustituye a `ShapeParameter`, que solo nombraba cuatro.** Con Groove son
/// siete, y con Timing y Delay serán nueve. Que la pantalla y el mapeo de CC
/// tengan que saber a qué familia pertenece cada parámetro para poder moverlo
/// sería un acoplamiento sin ninguna razón de dominio detrás.
final class TrackParameterTests: XCTestCase {

    // MARK: - La lista

    func testEveryAdjustableParameterIsNamed() {
        XCTAssertEqual(
            TrackParameter.allCases.map(\.description),
            [
                "Steps", "Pulses", "Rotate", "Division",
                "Velocity", "Sustain", "Probability", "Timing", "Delay",
            ]
        )
    }

    /// Los términos de la Pre Spec, en inglés y sin traducir, como exige
    /// `product-guidelines.md`.
    func testNamesAreThePreSpecTerms() {
        XCTAssertEqual(TrackParameter.steps.description, "Steps")
        XCTAssertEqual(TrackParameter.velocity.description, "Velocity")
        XCTAssertEqual(TrackParameter.probability.description, "Probability")
        XCTAssertEqual(TrackParameter.timing.description, "Timing")
        XCTAssertEqual(TrackParameter.delay.description, "Delay")
    }

    // MARK: - Ajustar un Track entero

    /// **El despacho es lo que sustituye al acoplamiento.** Quien mueve un knob
    /// ya no tiene que saber si toca Shape o Groove.
    func testAdjustingAShapeParameterLeavesGrooveAlone() {
        let track = Track(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!))
        let adjusted = track.applying(1, to: .steps)

        XCTAssertEqual(adjusted.shape.steps.count, 17 > 16 ? 16 : 17)
        XCTAssertEqual(adjusted.groove, track.groove)
        XCTAssertEqual(adjusted.pool, track.pool)
    }

    func testAdjustingAGrooveParameterLeavesShapeAndPoolAlone() {
        var pool = PitchPool()
        pool = pool.toggling(Pitch(60)!)
        let track = Track(shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!), pool: pool)

        let adjusted = track.applying(-10, to: .velocity)

        XCTAssertEqual(adjusted.groove.velocity.value, 90)
        XCTAssertEqual(adjusted.shape, track.shape)
        XCTAssertEqual(adjusted.pool, pool)
    }

    func testEveryParameterMovesSomething() {
        // Valores de partida lejos de todo extremo, para que un giro en
        // cualquiera de los nueve tenga sitio donde moverse.
        let track = Track(
            shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!, division: .quarter),
            groove: Groove(
                velocity: Velocity(64)!,
                sustain: Sustain(percent: 100)!,
                probability: Probability(percent: 50)!,
                timing: Timing(percent: 60)!,
                delay: Delay(percent: 0)!
            )
        )

        for parameter in TrackParameter.allCases {
            XCTAssertNotEqual(
                track.applying(1, to: parameter), track,
                "\(parameter) no se movió")
        }
    }

    /// Girar contra un extremo devuelve el mismo Track, que es lo que permite a
    /// `ControlInput` no publicar.
    func testTurningAgainstAnEndReturnsAnIdenticalTrack() {
        let track = Track(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(16)!),
            groove: Groove(
                velocity: Velocity(127)!,
                sustain: Sustain(percent: 200)!,
                probability: Probability(percent: 100)!,
                timing: Timing(percent: 75)!,
                delay: Delay(percent: 100)!
            )
        )

        for parameter in [
            TrackParameter.velocity, .sustain, .probability, .timing, .delay, .steps, .pulses,
        ] {
            XCTAssertEqual(track.applying(5, to: parameter), track, "\(parameter) se movió")
        }
    }
}

/// Tests de a qué familia pertenece cada parámetro.
///
/// **Es dominio, no presentación.** `product-guidelines.md` asigna un acento
/// cromático por familia funcional y dice que «el color codifica qué tipo de
/// parámetro es; nunca es decorativo». Qué tipo es lo sabe el motor; qué color
/// le toca lo decide la vista. Si la vista tuviera que deducir la familia de una
/// lista de casos, ese `switch` viviría donde no hay tests.
final class ParameterFamilyTests: XCTestCase {

    func testShapeParametersBelongToShape() {
        for parameter in [TrackParameter.steps, .pulses, .rotate, .division] {
            XCTAssertEqual(parameter.family, .shape, "\(parameter)")
        }
    }

    func testGrooveParametersBelongToGroove() {
        for parameter in [TrackParameter.velocity, .sustain, .probability, .timing, .delay] {
            XCTAssertEqual(parameter.family, .groove, "\(parameter)")
        }
    }

    /// Toda la lista está clasificada: un parámetro nuevo sin familia no
    /// compilaría, pero uno mal clasificado sí, y esto lo separa por conteo.
    ///
    /// **Cubre solo las dos familias de knob.** Desde que existe `.tonal` la
    /// lista de familias es mayor que la de familias alcanzables desde un
    /// parámetro, y esa diferencia es el punto: ver `testNoKnobParameterIsTonal`.
    func testEveryParameterHasAFamilyAndBothAreUsed() {
        let families = Set(TrackParameter.allCases.map(\.family))
        XCTAssertEqual(families, [.shape, .groove])
    }

    // MARK: - Tonal

    /// Las tres familias existen y `CaseIterable` las devuelve.
    ///
    /// **Tonal es una clasificación, no un parámetro** (FR4 de la rebanada 2 de
    /// la v2): existe para que el tercer tab saque su acento por la misma vía
    /// que los otros dos —`Palette.accent(for:)`— y no por un condicional en la
    /// vista, que es donde no hay tests.
    func testTheThreeFamiliesExist() {
        XCTAssertEqual(ParameterFamily.allCases, [.shape, .groove, .tonal])
    }

    /// **Ningún parámetro de knob es Tonal.** Scale y Root son táctiles y el
    /// pool se edita con pads: ninguno de los tres se ajusta con un delta, así
    /// que ninguno es un `TrackParameter`. Si algún día uno cae en `.tonal`, o
    /// es un error de clasificación o el modelo de entrada cambió — y las dos
    /// cosas merecen que esto falle.
    func testNoKnobParameterIsTonal() {
        for parameter in TrackParameter.allCases {
            XCTAssertNotEqual(parameter.family, .tonal, "\(parameter)")
        }
    }

    /// La clasificación de los nueve no se movió al añadir el caso.
    ///
    /// Los otros dos tests miran cada familia por separado; éste fija la lista
    /// entera de una vez, que es lo que se rompería si alguien reordenara los
    /// casos del `switch`.
    func testAddingTonalDoesNotReclassifyTheNine() {
        XCTAssertEqual(
            TrackParameter.allCases.map(\.family),
            [
                .shape, .shape, .shape, .shape,
                .groove, .groove, .groove, .groove, .groove,
            ]
        )
    }
}

/// Tests de cómo se lee Groove en pantalla.
final class GrooveDescriptionTests: XCTestCase {

    /// Mismo formato que `Shape.description`: los términos de la Pre Spec en
    /// inglés, el valor, y nada más. La app informa, no conversa.
    func testGrooveReadsAsItsThreeParametersAndValues() {
        let groove = Groove(
            velocity: Velocity(100)!,
            sustain: Sustain(percent: 100)!,
            probability: Probability(percent: 75)!
        )
        XCTAssertEqual(
            groove.description,
            "Velocity 100 · Sustain 100% · Probability 75% · Timing 50% · Delay 0%"
        )
    }

    /// El default de producto se lee sin sorpresas.
    func testTheDefaultGrooveReads() {
        XCTAssertEqual(
            Groove.default.description,
            "Velocity 100 · Sustain 100% · Probability 100% · Timing 50% · Delay 0%"
        )
    }

    /// **Los dos temporales se leen con su unidad y con su signo.** Timing es un
    /// porcentaje como los otros; Delay es el único que puede ser negativo, y
    /// adelantar y atrasar no se distinguen por el contexto: el signo tiene que
    /// verse.
    func testTheTemporalParametersReadWithTheirSign() {
        let groove = Groove(
            velocity: .default,
            sustain: .default,
            probability: .default,
            timing: Timing(percent: 67)!,
            delay: Delay(percent: -25)!
        )
        XCTAssertEqual(
            groove.description,
            "Velocity 100 · Sustain 100% · Probability 100% · Timing 67% · Delay -25%"
        )
    }
}
