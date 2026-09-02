import Engine
import XCTest
@testable import MIDI

/// Tests del controlador virtual de desarrollo.
///
/// `product-guidelines.md` lo pide como consecuencia de la frontera táctil/knob:
/// «probar el motor sin hardware exige un controlador virtual de desarrollo que
/// inyecte eventos MIDI relativos. Es una herramienta de test, excluida del
/// build de producción; **no es un modo de edición táctil por la puerta de
/// atrás**».
///
/// De ahí el criterio de estos tests: lo que inyecta tiene que ser
/// indistinguible de lo que manda un controlador real. Si fuera un atajo que
/// salta la decodificación, no probaría el camino que importa.
final class VirtualControllerTests: XCTestCase {

    private let controller = VirtualController()

    // MARK: - La ida y vuelta de la codificación

    func testEveryEncodableDeltaSurvivesARoundTrip() throws {
        for delta in (-63...63) where delta != 0 {
            let value = try XCTUnwrap(RelativeEncoding.twosComplement.value(for: delta), "\(delta)")
            XCTAssertEqual(RelativeEncoding.twosComplement.delta(from: value), delta)
        }
    }

    /// Fuera del rango codificable no se inventa un valor truncado: se rechaza.
    func testDeltasOutsideTheEncodableRangeAreRejected() {
        for delta in [0, 64, -64, 1_000, -1_000] {
            XCTAssertNil(RelativeEncoding.twosComplement.value(for: delta), "\(delta)")
        }
    }

    // MARK: - Lo que inyecta es un mensaje real

    func testTurningProducesAControlChangeOnTheMappedController() throws {
        let message = try XCTUnwrap(controller.turn(.pulses, by: 1))
        guard case .controlChange(_, let cc, let value) = message else {
            return XCTFail("no produjo un control change")
        }
        XCTAssertEqual(cc, ControlMapping.beatStepPro.controller(for: .pulses))
        XCTAssertEqual(RelativeEncoding.twosComplement.delta(from: value), 1)
    }

    func testTurningBackwardsEncodesANegativeDelta() throws {
        let message = try XCTUnwrap(controller.turn(.steps, by: -3))
        guard case .controlChange(_, _, let value) = message else {
            return XCTFail("no produjo un control change")
        }
        XCTAssertEqual(RelativeEncoding.twosComplement.delta(from: value), -3)
    }

    func testEveryParameterCanBeTurned() {
        for parameter in TrackParameter.allCases {
            XCTAssertNotNil(controller.turn(parameter, by: 1), "\(parameter)")
        }
    }

    func testAZeroTurnProducesNothing() {
        XCTAssertNil(controller.turn(.pulses, by: 0))
    }

    // MARK: - Indistinguible de un controlador real

    /// El criterio que justifica que esta herramienta exista: inyectar un giro
    /// tiene que producir exactamente el mismo efecto que el CC equivalente.
    func testInjectedTurnsHaveTheSameEffectAsRealMessages() throws {
        let steps = Steps(16)!
        let shape = Shape(steps: steps, pulses: Pulses(4)!)

        // Por el controlador virtual.
        let virtualHandoff = PatternHandoff(Cycle(shape: shape))
        let viaVirtual = ControlInput(track: Cycle(shape: shape), publishingTo: virtualHandoff)
        for _ in 0..<3 {
            viaVirtual.receive(try XCTUnwrap(controller.turn(.pulses, by: 1)))
        }

        // A mano, como lo mandaría el hardware.
        let realHandoff = PatternHandoff(Cycle(shape: shape))
        let viaReal = ControlInput(track: Cycle(shape: shape), publishingTo: realHandoff)
        let cc = try XCTUnwrap(ControlMapping.beatStepPro.controller(for: .pulses))
        for _ in 0..<3 {
            viaReal.receive(.controlChange(channel: MIDIChannel(1)!, controller: cc, value: 0x01))
        }

        XCTAssertEqual(viaVirtual.track, viaReal.track)
        XCTAssertEqual(virtualHandoff.load(), realHandoff.load())
        XCTAssertEqual(viaVirtual.track.shape.pulses.count, 7)
    }
}
