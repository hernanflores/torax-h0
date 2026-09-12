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
                "Repeats", "Time", "Ramp", "Pace",
                "Velocity", "Sustain", "Probability", "Timing", "Delay",
                "Pitch", "Harmony",
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
        let track = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!))
        let adjusted = track.applying(1, to: .steps)

        XCTAssertEqual(adjusted.shape.steps.count, 17 > 16 ? 16 : 17)
        XCTAssertEqual(adjusted.groove, track.groove)
        XCTAssertEqual(adjusted.pool, track.pool)
    }

    func testAdjustingAGrooveParameterLeavesShapeAndPoolAlone() {
        var pool = PitchPool()
        pool = pool.toggling(Pitch(60)!)
        let track = Cycle(shape: Shape(steps: Steps(12)!, pulses: Pulses(7)!), pool: pool)

        let adjusted = track.applying(-10, to: .velocity)

        XCTAssertEqual(adjusted.groove.velocity.value, 90)
        XCTAssertEqual(adjusted.shape, track.shape)
        XCTAssertEqual(adjusted.pool, pool)
    }

    func testEveryParameterMovesSomething() {
        // Valores de partida lejos de todo extremo, para que un giro en
        // cualquiera de los nueve tenga sitio donde moverse.
        let track = Cycle(
            shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!, division: .quarter),
            // Un pool con sitio: Harmony no mueve nada con menos de dos pitches.
            pool: PitchPool().inserting(Pitch(60)!).inserting(Pitch(67)!),
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
        let track = Cycle(
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
    /// **Las tres familias tienen knob desde el 2026-09-12**, cuando Pitch entró
    /// en Tonal (`pitch-harmony_20260912`).
    func testEveryParameterHasAFamilyAndAllThreeAreUsed() {
        let families = Set(TrackParameter.allCases.map(\.family))
        XCTAssertEqual(families, [.shape, .groove, .tonal])
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

    /// **Solo Pitch y Harmony son Tonal.** Scale y Root siguen siendo táctiles y
    /// el pool se sigue editando con pads, así que ninguno de los tres es un
    /// `TrackParameter`. Pitch y Harmony sí lo son: transforman el pool con un
    /// delta.
    ///
    /// > **Hasta el 2026-09-12 este test fijaba que ningún parámetro de knob era
    /// > Tonal**, y avisaba de que fallaría el día que el modelo de entrada
    /// > cambiara. Ese día es `pitch-harmony_20260912`.
    func testOnlyPitchAndHarmonyAreTonal() {
        XCTAssertEqual(
            TrackParameter.allCases.filter { $0.family == .tonal }, [.pitch, .harmony])
    }

    /// La clasificación no se movió al añadir casos.
    ///
    /// **Trece desde el 2026-09-07**: los cuatro del Note Repeater entran en la
    /// familia Shape, detrás de Division, porque son una capa sobre el ritmo y
    /// no una familia nueva. **Catorce desde el 2026-09-12**: Pitch cierra la
    /// lista en Tonal. **Quince** con Harmony, detrás.
    ///
    /// Los otros dos tests miran cada familia por separado; éste fija la lista
    /// entera de una vez, que es lo que se rompería si alguien reordenara los
    /// casos del `switch`.
    func testAddingTonalDoesNotReclassifyTheNine() {
        XCTAssertEqual(
            TrackParameter.allCases.map(\.family),
            [
                .shape, .shape, .shape, .shape,
                .shape, .shape, .shape, .shape,
                .groove, .groove, .groove, .groove, .groove,
                .tonal, .tonal,
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
