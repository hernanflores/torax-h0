import Engine
import XCTest

@testable import MIDI

/// Tests de Pitch y Harmony en un mapeo aprendido (`pitch-harmony_20260912`,
/// FR15).
///
/// **Se aprenden como cualquier parámetro**, y un proyecto guardado antes de que
/// existieran los recibe con su número de fábrica —75 y 76— **solo si ese
/// número está libre**. Nada aprendido se pisa, y un parámetro que el usuario
/// dejó sin control a propósito sigue sin control: lo que se completa es lo que
/// el fichero no conocía (`ControlNumbers.knownParameters`).
final class TonalLearnCompletionTests: XCTestCase {

    private let beforeTonal = Set(TrackParameter.allCases).subtracting([.pitch, .harmony])

    /// El preset de fábrica de antes del track: los trece de siempre.
    private var oldFactory: [TrackParameter: Int] {
        ControlMapping.beatStepPro.numbers.assignments.filter { beforeTonal.contains($0.key) }
    }

    private func restored(_ assignments: [TrackParameter: Int], known: Set<TrackParameter>)
        -> ControlMapping
    {
        ControlMapping(
            ControlNumbers(
                assignments: assignments,
                padBlock: Int(ControlMapping.defaultPadBlock.value),
                knobBlock: ControlMapping.defaultKnobBlock.number,
                stepButtonBlock: ControlMapping.defaultStepButtonBlock.number,
                knownParameters: known))
    }

    // MARK: - Aprender

    func testPitchAndHarmonyCanBeLearned() {
        let mapping = ControlMapping.beatStepPro
            .assigning(MIDIController(20)!, to: .pitch)
            .assigning(MIDIController(21)!, to: .harmony)

        XCTAssertEqual(mapping.controller(for: .pitch), MIDIController(20))
        XCTAssertEqual(mapping.controller(for: .harmony), MIDIController(21))
        XCTAssertNil(mapping.parameter(for: MIDIController(75)!), "el 75 no quedó libre")
    }

    // MARK: - Completar un proyecto de antes

    /// Un proyecto de antes con el preset de siempre recibe los dos knobs.
    func testAnOldProjectGetsBothTonalKnobs() {
        let mapping = restored(oldFactory, known: beforeTonal)
        XCTAssertEqual(mapping.controller(for: .pitch)?.number, 75)
        XCTAssertEqual(mapping.controller(for: .harmony)?.number, 76)
        XCTAssertEqual(mapping, .beatStepPro)
    }

    /// **Un número ocupado no se pisa**: si el usuario aprendió Steps en el 75,
    /// Pitch se queda sin control y Harmony recibe el 76.
    func testAnOccupiedNumberIsNotTaken() {
        var learned = oldFactory
        learned[.steps] = 75
        let mapping = restored(learned, known: beforeTonal)

        XCTAssertEqual(mapping.parameter(for: MIDIController(75)!), .steps)
        XCTAssertNil(mapping.controller(for: .pitch))
        XCTAssertEqual(mapping.controller(for: .harmony)?.number, 76)
        XCTAssertEqual(mapping.parametersWithoutController, [.pitch], "el silencio se anuncia")
    }

    /// **Un parámetro conocido sin control sigue sin control.** El usuario lo
    /// dejó así aprendiendo encima; completarlo sería deshacer su decisión.
    func testAKnownParameterWithoutControlIsRespected() {
        let mapping = restored(oldFactory, known: Set(TrackParameter.allCases))
        XCTAssertNil(mapping.controller(for: .pitch))
        XCTAssertNil(mapping.controller(for: .harmony))
    }

    /// Un número de fábrica que cae dentro del bloque de step buttons aprendido
    /// no se usa: completar no puede crear un conflicto.
    func testCompletingNeverCreatesAConflict() {
        let mapping = ControlMapping(
            ControlNumbers(
                assignments: [.steps: 20],
                padBlock: 36,
                knobBlock: 20,
                stepButtonBlock: 70,
                knownParameters: beforeTonal))

        XCTAssertFalse(mapping.hasConflict)
        XCTAssertEqual(mapping.controller(for: .steps)?.number, 20, "cayó en el de fábrica")
        XCTAssertNil(mapping.controller(for: .pitch))
        XCTAssertNil(mapping.controller(for: .harmony))
    }

    /// El mapeo de la sesión, ida y vuelta por números, no inventa nada.
    func testTheSessionRoundTripAddsNothing() {
        let learned = ControlMapping.beatStepPro
            .assigning(MIDIController(75)!, to: .steps)
            .assigning(MIDIController(78)!, to: .harmony)
        XCTAssertEqual(ControlMapping(learned.numbers), learned)
    }
}
