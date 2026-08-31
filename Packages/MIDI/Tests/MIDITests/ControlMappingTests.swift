import Engine
import XCTest
@testable import MIDI

/// Tests del mapeo de controladores a parámetros de Shape.
final class ControlMappingTests: XCTestCase {

    private let mapping = ControlMapping.beatStepPro

    // MARK: - Un CC mueve su parámetro y solo el suyo

    func testEveryTrackParameterHasAController() {
        for parameter in TrackParameter.allCases {
            XCTAssertNotNil(mapping.controller(for: parameter), "\(parameter) no es alcanzable")
        }
    }

    func testEachControllerMapsBackToItsOwnParameter() throws {
        for parameter in TrackParameter.allCases {
            let controller = try XCTUnwrap(mapping.controller(for: parameter))
            XCTAssertEqual(mapping.parameter(for: controller), parameter)
        }
    }

    /// Dos parámetros no pueden compartir controlador: un knob movería dos cosas.
    func testNoTwoParametersShareAController() {
        let controllers = TrackParameter.allCases.compactMap { mapping.controller(for: $0) }
        XCTAssertEqual(Set(controllers).count, controllers.count, "hay controladores duplicados")
    }

    // MARK: - Lo no mapeado se ignora en silencio

    /// Un controlador sin asignar no es un error: en una sesión real llegan
    /// mensajes de todo tipo, y no es asunto del mapeo quejarse de ellos.
    func testUnmappedControllersAreIgnored() throws {
        let assigned = Set(
            TrackParameter.allCases.compactMap { mapping.controller(for: $0)?.number })
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
        guard case .controlChange(_, let controller, let value) = message else {
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

/// Tests del mapeo ampliado a los nueve parámetros.
///
/// Los cinco CC de Groove entran en el mismo bloque contiguo que los de Shape:
/// 70–78. Los de propósito general de la especificación MIDI llegan hasta el 79,
/// así que los nueve caben sin salir del rango que la especificación deja sin
/// significado fijo.
final class GrooveControlMappingTests: XCTestCase {

    func testEveryTrackParameterHasAController() {
        for parameter in TrackParameter.allCases {
            XCTAssertNotNil(
                ControlMapping.beatStepPro.controller(for: parameter),
                "\(parameter) no tiene controlador")
        }
    }

    /// **Ningún CC mueve dos parámetros.** Un choque haría que girar un knob
    /// moviera algo distinto de lo que dice la etiqueta, y ningún test de un
    /// parámetro suelto lo detectaría.
    func testNoControllerIsSharedByTwoParameters() {
        let numbers = TrackParameter.allCases.compactMap {
            ControlMapping.beatStepPro.controller(for: $0)?.number
        }
        XCTAssertEqual(Set(numbers).count, numbers.count, "dos parámetros comparten CC: \(numbers)")
    }

    func testTheGrooveControllersResolveBack() {
        let expected: [Int: TrackParameter] = [
            74: .velocity, 75: .sustain, 76: .probability, 77: .timing, 78: .delay,
        ]

        for (number, parameter) in expected {
            XCTAssertEqual(
                ControlMapping.beatStepPro.parameter(for: MIDIController(number)!),
                parameter)
        }
    }

    /// Los cuatro de Shape no se movieron de sitio: el mapeo se amplió, no se
    /// rehízo.
    func testTheShapeControllersDidNotMove() {
        let expected: [Int: TrackParameter] = [70: .steps, 71: .pulses, 72: .rotate, 73: .division]

        for (number, parameter) in expected {
            XCTAssertEqual(
                ControlMapping.beatStepPro.parameter(for: MIDIController(number)!),
                parameter)
        }
    }

    /// Un CC sin asignar se sigue ignorando en silencio: en una sesión real
    /// llegan mensajes de todo tipo y no es asunto del mapeo quejarse.
    ///
    /// **El CC sin asignar se busca, no se escribe.** Estaba escrito como 77, y
    /// la rebanada 6 se lo dio a Timing: el test falló por un comportamiento que
    /// no había cambiado. Es la misma lección que `ControlInputTests` dejó
    /// anotada al añadir 1/32 — lo que cambia es el dominio, y el test tiene que
    /// leerlo de ahí.
    func testAnUnassignedControllerIsStillIgnored() {
        let assigned = Set(
            TrackParameter.allCases.compactMap {
                ControlMapping.beatStepPro.controller(for: $0)?.number
            })
        guard let unassigned = (0...127).first(where: { !assigned.contains($0) }) else {
            return XCTFail("el mapeo provisional ocupó los 128 controladores")
        }

        XCTAssertNil(ControlMapping.beatStepPro.parameter(for: MIDIController(unassigned)!))
    }
}

/// Tests de que un giro de Groove publica, y de que no destruye nada.
final class GrooveTurnsTests: XCTestCase {

    private let channel = MIDIChannel(1)!

    private func turn(_ parameter: TrackParameter, by value: UInt8) -> MIDIMessage {
        .controlChange(
            channel: channel,
            controller: ControlMapping.beatStepPro.controller(for: parameter)!,
            value: value
        )
    }

    private func makeInput() -> (ControlInput, PatternHandoff) {
        var pool = PitchPool()
        pool = pool.toggling(Pitch(60)!)
        pool = pool.toggling(Pitch(64)!)
        let track = Track(
            shape: Shape(steps: Steps(12)!, pulses: Pulses(5)!, rotate: Rotate(2)),
            pool: pool,
            groove: Groove(
                velocity: Velocity(64)!,
                sustain: Sustain(percent: 100)!,
                probability: Probability(percent: 50)!
            )
        )
        let handoff = PatternHandoff(track)
        return (ControlInput(track: track, publishingTo: handoff), handoff)
    }

    func testEachGrooveParameterPublishesWhenTurned() {
        for parameter in [TrackParameter.velocity, .sustain, .probability] {
            let (input, _) = makeInput()
            XCTAssertTrue(input.receive(turn(parameter, by: 0x01)), "\(parameter) no respondió")
        }
    }

    /// **Girar Groove conserva Shape y pool, y al revés.** Es la regla de
    /// destructividad de `product-guidelines.md` sobre la estructura entera del
    /// Track, no solo sobre el pool tonal.
    func testTurningGrooveKeepsShapeAndPool() {
        let (input, _) = makeInput()
        let before = input.track

        XCTAssertTrue(input.receive(turn(.velocity, by: 0x01)))

        XCTAssertEqual(input.track.shape, before.shape)
        XCTAssertEqual(input.track.pool, before.pool)
        XCTAssertEqual(input.track.groove.velocity.value, 65)
    }

    func testTurningShapeKeepsGrooveAndPool() {
        let (input, _) = makeInput()
        let before = input.track

        XCTAssertTrue(input.receive(turn(.pulses, by: 0x01)))

        XCTAssertEqual(input.track.groove, before.groove)
        XCTAssertEqual(input.track.pool, before.pool)
        XCTAssertEqual(input.track.shape.pulses.count, 6)
    }

    /// Girar contra un extremo no publica: el valor ya estaba ahí.
    func testTurningAGrooveParameterAgainstItsEndDoesNotPublish() {
        var pool = PitchPool()
        pool = pool.toggling(Pitch(60)!)
        let track = Track(
            shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!),
            pool: pool,
            groove: Groove(velocity: Velocity(127)!, sustain: .default, probability: .default)
        )
        let input = ControlInput(track: track, publishingTo: PatternHandoff(track))

        XCTAssertFalse(input.receive(turn(.velocity, by: 0x01)))
    }
}
