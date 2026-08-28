import Engine
import XCTest
@testable import MIDI

/// Tests del mapeo de controladores a parámetros de Shape.
final class ControlMappingTests: XCTestCase {

    private let mapping = ControlMapping.provisional

    // MARK: - Un CC mueve su parámetro y solo el suyo

    func testEveryShapeParameterHasAController() {
        for parameter in ShapeParameter.allCases {
            XCTAssertNotNil(mapping.controller(for: parameter), "\(parameter) no es alcanzable")
        }
    }

    func testEachControllerMapsBackToItsOwnParameter() throws {
        for parameter in ShapeParameter.allCases {
            let controller = try XCTUnwrap(mapping.controller(for: parameter))
            XCTAssertEqual(mapping.parameter(for: controller), parameter)
        }
    }

    /// Dos parámetros no pueden compartir controlador: un knob movería dos cosas.
    func testNoTwoParametersShareAController() {
        let controllers = ShapeParameter.allCases.compactMap { mapping.controller(for: $0) }
        XCTAssertEqual(Set(controllers).count, controllers.count, "hay controladores duplicados")
    }

    // MARK: - Lo no mapeado se ignora en silencio

    /// Un controlador sin asignar no es un error: en una sesión real llegan
    /// mensajes de todo tipo, y no es asunto del mapeo quejarse de ellos.
    func testUnmappedControllersAreIgnored() throws {
        let assigned = Set(ShapeParameter.allCases.compactMap { mapping.controller(for: $0)?.number })
        for number in 0...127 where !assigned.contains(number) {
            let controller = try XCTUnwrap(MIDIController(number))
            XCTAssertNil(mapping.parameter(for: controller), "CC \(number)")
        }
    }

    // MARK: - El mensaje de control

    func testControlChangeCarriesItsControllerAndValue() throws {
        let message = MIDIMessage.controlChange(
            channel: try XCTUnwrap(MIDIChannel(1)),
            controller: try XCTUnwrap(MIDIController(74)),
            value: 0x01
        )
        guard case let .controlChange(_, controller, value) = message else {
            return XCTFail("no es un control change")
        }
        XCTAssertEqual(controller.number, 74)
        XCTAssertEqual(value, 0x01)
    }

    /// Se empaqueta como mensaje de canal MIDI 1.0 con status `0xB0`.
    func testControlChangePacksWithTheControlChangeStatus() throws {
        let message = MIDIMessage.controlChange(
            channel: try XCTUnwrap(MIDIChannel(1)),
            controller: try XCTUnwrap(MIDIController(74)),
            value: 0x7F
        )
        let word = message.universalPacketWord(group: 0)
        XCTAssertEqual((word >> 16) & 0xFF, 0xB0, "status incorrecto")
        XCTAssertEqual((word >> 8) & 0xFF, 74)
        XCTAssertEqual(word & 0xFF, 0x7F)
    }

    func testControllerRejectsValuesOutsideTheMIDIRange() {
        XCTAssertNil(MIDIController(-1))
        XCTAssertNil(MIDIController(128))
        XCTAssertEqual(MIDIController(0)?.number, 0)
        XCTAssertEqual(MIDIController(127)?.number, 127)
    }
}
