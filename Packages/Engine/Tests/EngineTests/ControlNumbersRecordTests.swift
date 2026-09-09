import Foundation
import XCTest

@testable import Engine

/// Tests de que el mapeo aprendido sobrevive al disco.
///
/// **Ausente significa el preset de fábrica** (`midi-learn_20260908`, FR17), y
/// esa es la decisión que evita subir `schemaVersion`: un `Project` sin números
/// es un usuario que nunca aprendió nada, que es lo que un opcional ya significa
/// en este record — el mismo criterio que `destinationName` y `sourceName`.
final class ControlNumbersRecordTests: XCTestCase {

    // MARK: - La versión no sube (FR17)

    /// **La condición que hace segura toda esta fase.** `validated()` exige
    /// igualdad exacta, así que subir la versión apartaría todos los ficheros
    /// existentes.
    func testTheSchemaVersionStaysAtOne() {
        XCTAssertEqual(ProjectRecord.currentSchemaVersion, 1)
    }

    /// Un fichero escrito antes de este track no lleva la clave, y tiene que
    /// abrir.
    func testAProjectWrittenBeforeThisTrackStillDecodes() throws {
        let json = """
            {
              "schemaVersion": 1,
              "selectedBank": 2,
              "selectedPattern": 3,
              "selectedTrack": 4,
              "clockSource": "external"
            }
            """

        let record = try JSONDecoder().decode(ProjectRecord.self, from: Data(json.utf8))

        XCTAssertEqual(try record.validated().selectedBank, 2)
        XCTAssertNil(record.controlNumbers)
    }

    /// Y abre **con el preset de fábrica**, que es lo que dice la ausencia.
    func testAProjectWithoutNumbersRestoresWithoutThem() throws {
        let json = """
            {
              "schemaVersion": 1,
              "selectedBank": 0,
              "selectedPattern": 0,
              "selectedTrack": 0,
              "clockSource": "internal"
            }
            """

        let record = try JSONDecoder().decode(ProjectRecord.self, from: Data(json.utf8))

        XCTAssertNil(record.project(with: []).controlNumbers)
    }

    /// Un fichero que declare la versión 2 se sigue apartando: esta rebanada no
    /// estrena la subida.
    func testAFutureVersionIsStillRejected() {
        let record = ProjectRecord(Project(), schemaVersion: 2)

        XCTAssertThrowsError(try record.validated())
    }

    // MARK: - Ida y vuelta

    func testTheNumbersSurviveTheRoundTrip() throws {
        let numbers = ControlNumbers(
            assignments: [.steps: 20, .pace: 31],
            padBlock: 60,
            knobBlock: 20,
            stepButtonBlock: 40
        )
        let project = Project().remembering(controlNumbers: numbers)

        let returned = try decoded(ProjectRecord(project)).project(with: []).controlNumbers

        XCTAssertEqual(returned, numbers)
    }

    /// Los trece parámetros se escriben y se leen. Sin esto, añadir uno al motor
    /// dejaría un mapeo aprendido perdiendo justo el nuevo, en silencio.
    func testEveryParameterHasAStableKey() throws {
        let assignments = Dictionary(
            uniqueKeysWithValues: TrackParameter.allCases.enumerated().map { ($1, 20 + $0) })
        let numbers = ControlNumbers(
            assignments: assignments, padBlock: 36, knobBlock: 70, stepButtonBlock: 102)

        let returned = try decoded(ProjectRecord(Project().remembering(controlNumbers: numbers)))
            .project(with: []).controlNumbers

        XCTAssertEqual(returned?.assignments, assignments)
    }

    /// **Las claves son del disco, no de la pantalla.** Atar el fichero a lo que
    /// se lee en la interfaz haría que renombrar una etiqueta rompiera mapeos
    /// guardados — el mismo criterio que separa `scale` de `Scale.name`.
    func testTheKeysAreLowercaseAndStable() {
        XCTAssertEqual(ControlNumbersRecord.key(for: .steps), "steps")
        XCTAssertEqual(ControlNumbersRecord.key(for: .repeatTime), "repeattime")
        XCTAssertEqual(ControlNumbersRecord.key(for: .probability), "probability")
    }

    /// Una clave que esta app no conoce **se descarta y el resto entra**. Un
    /// fichero de una versión futura no puede dejar la app sin mapeo.
    func testAnUnknownKeyIsIgnoredWithoutLosingTheRest() {
        let record = ControlNumbersRecord(
            assignments: ["steps": 20, "quantum": 99],
            padBlock: 36,
            knobBlock: 70,
            stepButtonBlock: 102
        )

        let numbers = record.numbers

        XCTAssertEqual(numbers.assignments, [.steps: 20])
    }

    /// Un mapeo que no asigna nada es válido y se guarda como tal: no es lo
    /// mismo que no haber aprendido nunca.
    func testAnEmptyAssignmentTableIsNotTheSameAsAbsent() throws {
        let numbers = ControlNumbers(
            assignments: [:], padBlock: 36, knobBlock: 70, stepButtonBlock: 102)

        let returned = try decoded(ProjectRecord(Project().remembering(controlNumbers: numbers)))
            .project(with: []).controlNumbers

        XCTAssertEqual(returned, numbers)
        XCTAssertNotNil(returned)
    }

    // MARK: - Lo demás del Project no se mueve

    func testRememberingTheNumbersKeepsEverythingElse() {
        let project = Project()
            .selectingBank(3)
            .withClockSource(.external)
            .remembering(destinationNamed: "Synth", sourceNamed: "BeatStep")

        let after = project.remembering(
            controlNumbers: ControlNumbers(
                assignments: [:], padBlock: 36, knobBlock: 70, stepButtonBlock: 102))

        XCTAssertEqual(after.selectedBank, 3)
        XCTAssertEqual(after.clockSource, .external)
        XCTAssertEqual(after.destinationName, "Synth")
        XCTAssertEqual(after.sourceName, "BeatStep")
    }

    // MARK: -

    private func decoded(_ record: ProjectRecord) throws -> ProjectRecord {
        try JSONDecoder().decode(ProjectRecord.self, from: JSONEncoder().encode(record))
    }
}
