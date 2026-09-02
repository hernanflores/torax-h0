import XCTest

@testable import Engine

/// Tests del valor grande transitorio.
///
/// **Se llamaba `ShapeChange` y comparaba dos Shapes.** Groove vive en `Track`,
/// así que la comparación sube un nivel: dos Tracks. Lo que no cambia es la
/// razón de existir —`product-guidelines.md` pide que al girar un knob su valor
/// aparezca en grande— ni la regla de responder por el resultado y no por la
/// intención.
final class ParameterChangeTests: XCTestCase {

    /// Valores de partida lejos de todo extremo, para que un giro en cualquiera
    /// de los siete tenga sitio donde moverse.
    private let track = Cycle(
        shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!, division: .quarter),
        groove: Groove(
            velocity: Velocity(64)!,
            sustain: Sustain(percent: 100)!,
            probability: Probability(percent: 50)!
        )
    )

    private func change(_ delta: Int, _ parameter: TrackParameter) -> ParameterChange? {
        ParameterChange(from: track, to: track.applying(delta, to: parameter))
    }

    // MARK: - Los tres nuevos

    func testVelocityReadsAsItsPreSpecTermAndValue() {
        let change = change(1, .velocity)
        XCTAssertEqual(change?.parameter, .velocity)
        XCTAssertEqual(change?.description, "Velocity 65")
    }

    /// Sustain y Probability llevan el signo de porcentaje; Velocity no, porque
    /// vive en la unidad MIDI y no en un porcentaje.
    func testSustainAndProbabilityReadAsPercentages() {
        XCTAssertEqual(change(10, .sustain)?.description, "Sustain 110%")
        XCTAssertEqual(change(10, .probability)?.description, "Probability 60%")
    }

    // MARK: - Lo de Shape no cambió

    /// **El criterio del renombrado.** Estos cuatro daban exactamente estas
    /// descripciones antes de que existiera Groove, y las siguen dando: es un
    /// renombrado con casos nuevos, no un cambio de comportamiento.
    func testTheShapeParametersReadExactlyAsBefore() {
        XCTAssertEqual(change(1, .steps)?.description, "Steps 9")
        XCTAssertEqual(change(1, .pulses)?.description, "Pulses 5")
        XCTAssertEqual(change(1, .rotate)?.description, "Rotate 1")
        XCTAssertEqual(change(1, .division)?.description, "Division 1/8")
    }

    /// El valor pedido, no `effectivePulses`: el knob está en ese número y
    /// mostrar el otro haría creer que se perdió.
    func testPulsesShowsTheIntendedValueNotTheEffectiveOne() {
        let narrow = Cycle(shape: Shape(steps: Steps(4)!, pulses: Pulses(4)!))
        let change = ParameterChange(from: narrow, to: narrow.applying(3, to: .pulses))

        XCTAssertEqual(change?.description, "Pulses 7")
    }

    // MARK: - Cuándo no hay nada que anunciar

    /// `nil` es el caso común y no es un error: llegan mensajes que no mueven
    /// nada y giros contra un extremo.
    func testNoChangeAnnouncesNothing() {
        XCTAssertNil(ParameterChange(from: track, to: track))
    }

    func testTurningAgainstAnEndAnnouncesNothing() {
        let loud = Cycle(
            shape: track.shape,
            groove: Groove(velocity: Velocity(127)!, sustain: .default, probability: .default)
        )
        XCTAssertNil(ParameterChange(from: loud, to: loud.applying(5, to: .velocity)))
    }

    // MARK: - Cambiar el pool no es un parámetro

    /// El pool se edita con pads y tiene su propia representación en pantalla;
    /// anunciarlo como un valor grande sería tratarlo como lo que no es.
    func testEditingThePoolAnnouncesNothing() {
        let withPool = Cycle(
            shape: track.shape,
            pool: PitchPool().toggling(Pitch(60)!),
            groove: track.groove
        )
        XCTAssertNil(ParameterChange(from: track, to: withPool))
    }

    // MARK: - Solo el primero que difiera

    func testOnlyTheFirstDifferenceIsAnnounced() {
        let other = Cycle(
            shape: Shape(steps: Steps(12)!, pulses: Pulses(4)!, division: .quarter),
            groove: Groove(velocity: Velocity(100)!, sustain: .default, probability: .default)
        )
        XCTAssertEqual(ParameterChange(from: track, to: other)?.parameter, .steps)
    }
}

/// Tests de los dos parámetros temporales en el valor grande transitorio.
///
/// Llegan con la rebanada 6, y con ellos el primer valor que puede ser negativo.
final class TemporalParameterChangeTests: XCTestCase {

    private func track(timing: Int = 50, delay: Int = 0) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!),
            groove: Groove(
                velocity: .default,
                sustain: .default,
                probability: .default,
                timing: Timing(percent: timing)!,
                delay: Delay(percent: delay)!
            )
        )
    }

    func testTimingAnnouncesItself() {
        let change = ParameterChange(from: track(), to: track(timing: 67))

        XCTAssertEqual(change?.parameter, .timing)
        XCTAssertEqual(change?.description, "Timing 67%")
    }

    /// **El signo se ve.** Es el único parámetro que puede ser negativo, y
    /// adelantar y atrasar no se distinguen por el contexto.
    func testDelayAnnouncesItselfWithItsSign() {
        XCTAssertEqual(
            ParameterChange(from: track(), to: track(delay: -25))?.description, "Delay -25%")
        XCTAssertEqual(
            ParameterChange(from: track(), to: track(delay: 25))?.description, "Delay 25%")
    }

    /// El cero se anuncia como cero, sin signo: es la rejilla, no un
    /// desplazamiento de cero unidades.
    func testDelayBackOnTheGridReadsAsZero() {
        XCTAssertEqual(
            ParameterChange(from: track(delay: -25), to: track())?.description, "Delay 0%")
    }

    /// Un Track idéntico sigue sin anunciar nada, con los dos nuevos dentro.
    func testAnIdenticalTrackStillAnnouncesNothing() {
        XCTAssertNil(
            ParameterChange(from: track(timing: 67, delay: -25), to: track(timing: 67, delay: -25)))
    }
}
