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
                "Velocity", "Sustain", "Probability",
            ]
        )
    }

    /// Los términos de la Pre Spec, en inglés y sin traducir, como exige
    /// `product-guidelines.md`.
    func testNamesAreThePreSpecTerms() {
        XCTAssertEqual(TrackParameter.steps.description, "Steps")
        XCTAssertEqual(TrackParameter.velocity.description, "Velocity")
        XCTAssertEqual(TrackParameter.probability.description, "Probability")
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
        // cualquiera de los siete tenga sitio donde moverse.
        let track = Track(
            shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!, division: .quarter),
            groove: Groove(
                velocity: Velocity(64)!,
                sustain: Sustain(percent: 100)!,
                probability: Probability(percent: 50)!
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
                probability: Probability(percent: 100)!
            )
        )

        for parameter in [TrackParameter.velocity, .sustain, .probability, .steps, .pulses] {
            XCTAssertEqual(track.applying(5, to: parameter), track, "\(parameter) se movió")
        }
    }
}
