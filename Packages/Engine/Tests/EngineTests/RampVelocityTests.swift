import XCTest

@testable import Engine

/// Tests de la curva de velocity del Note Repeater.
///
/// **El Pulse original no participa de la rampa.** Suena siempre a la Velocity
/// del Track, y la curva recorre solo las repeticiones — la repetición `k`, de 1
/// a `n`. El Pulse es `k = 0` y devuelve la Velocity intacta en los dos
/// sentidos.
///
/// **Con Ramp negativo la curva acota en 1 y no en 0.** Velocity 0 es note-off
/// en MIDI 1.0, así que una rampa que llegara a cero emitiría un apagado
/// disfrazado de nota. Es la misma razón por la que `Velocity` excluye el cero.
final class RampVelocityTests: XCTestCase {

    private let base = Velocity(100)!

    // MARK: - Sin curva

    /// Con Ramp 0 las `n` repeticiones suenan a la Velocity del Track: es el
    /// default, y con él la rebanada no cambia nada de lo entregado.
    func testWithoutRampEveryRepetitionSoundsAtTheTrackVelocity() {
        for k in 0...8 {
            XCTAssertEqual(
                Ramp.default.velocity(forRepetition: k, of: 8, from: base).value,
                100,
                "repetición \(k)"
            )
        }
    }

    // MARK: - Los extremos

    /// Con +100 la última repetición llega a 127.
    func testFullPositiveRampReachesTheTopOnTheLastRepetition() {
        let ramp = Ramp(percent: 100)!
        XCTAssertEqual(ramp.velocity(forRepetition: 4, of: 4, from: base).value, 127)
    }

    /// **Con −100 la última llega a 1, no a 0.**
    func testFullNegativeRampStopsAtOneAndNotAtZero() {
        let ramp = Ramp(percent: -100)!
        XCTAssertEqual(ramp.velocity(forRepetition: 4, of: 4, from: base).value, 1)
    }

    /// La curva es progresiva: cada repetición se acerca más al objetivo que la
    /// anterior, y ninguna se pasa.
    func testThePositiveRampRisesStepByStep() {
        let ramp = Ramp(percent: 100)!
        let values = (1...4).map { ramp.velocity(forRepetition: $0, of: 4, from: base).value }
        XCTAssertEqual(values, [106, 113, 120, 127])
    }

    func testTheNegativeRampFallsStepByStep() {
        let ramp = Ramp(percent: -100)!
        let values = (1...4).map { ramp.velocity(forRepetition: $0, of: 4, from: base).value }
        XCTAssertEqual(values, [76, 51, 26, 1])
    }

    /// Con `|ramp|` intermedio la última se queda a medio camino: con 50 y V=100
    /// el objetivo está a 27 de distancia, así que la última sube 13.
    func testAHalfRampCoversHalfTheDistance() {
        let up = Ramp(percent: 50)!
        XCTAssertEqual(up.velocity(forRepetition: 4, of: 4, from: base).value, 113)

        let down = Ramp(percent: -50)!
        XCTAssertEqual(down.velocity(forRepetition: 4, of: 4, from: base).value, 51)
    }

    // MARK: - El Pulse queda fuera

    /// El Pulse original suena a la Velocity del Track en los dos sentidos.
    func testThePulseKeepsTheTrackVelocityInBothDirections() {
        for percent in [-100, -40, 40, 100] {
            let ramp = Ramp(percent: percent)!
            XCTAssertEqual(
                ramp.velocity(forRepetition: 0, of: 8, from: base).value,
                100,
                "ramp \(percent)"
            )
        }
    }

    // MARK: - Relativa al Track

    /// **Mover la Velocity del Track mueve la rampa entera con ella**, que es lo
    /// que «relativo a la Velocity general del Track» significa en la Pre Spec.
    func testMovingTheTrackVelocityMovesTheWholeRamp() {
        let ramp = Ramp(percent: 50)!
        let quiet = Velocity(40)!
        let loud = Velocity(120)!

        let fromQuiet = (1...4).map { ramp.velocity(forRepetition: $0, of: 4, from: quiet).value }
        let fromLoud = (1...4).map { ramp.velocity(forRepetition: $0, of: 4, from: loud).value }

        XCTAssertEqual(fromQuiet.first, 50)
        XCTAssertEqual(fromLoud.first, 120)
        XCTAssertTrue(zip(fromQuiet, fromLoud).allSatisfy { $0 < $1 })
    }

    /// La curva nunca se sale del rango emisible, sea cual sea el punto de
    /// partida. Recorre los extremos de Velocity y de Ramp.
    func testTheRampNeverLeavesTheEmittableRange() {
        for velocity in [1, 64, 127] {
            for percent in [-100, -1, 0, 1, 100] {
                let ramp = Ramp(percent: percent)!
                for k in 0...8 {
                    let value = ramp.velocity(
                        forRepetition: k, of: 8, from: Velocity(velocity)!
                    ).value
                    XCTAssertTrue(
                        Velocity.validRange.contains(value),
                        "V \(velocity), ramp \(percent), repetición \(k): \(value)"
                    )
                }
            }
        }
    }

    /// Con una sola repetición la curva llega entera en ella: no hay tirada que
    /// recorrer.
    func testASingleRepetitionReachesTheTargetOnItsOwn() {
        XCTAssertEqual(
            Ramp(percent: 100)!.velocity(forRepetition: 1, of: 1, from: base).value, 127)
        XCTAssertEqual(
            Ramp(percent: -100)!.velocity(forRepetition: 1, of: 1, from: base).value, 1)
    }
}
