import Foundation
import XCTest

@testable import Engine

/// Tests de la lista de parámetros que conocía la app al guardar el mapeo
/// (`pitch-harmony_20260912`, FR15).
///
/// **Existe para distinguir dos silencios que el mapeo guarda igual.** Un
/// parámetro sin entrada en `assignments` puede ser uno que el usuario dejó sin
/// control aprendiendo encima —un estado válido que hay que respetar— o uno que
/// la app que escribió el fichero ni siquiera tenía. Solo el segundo se completa
/// con su número de fábrica al abrir.
///
/// **Un fichero sin la lista es anterior a este track**, así que lo único que no
/// conocía son Pitch y Harmony.
final class KnownParametersRecordTests: XCTestCase {

    private func dictionary(from record: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decoded(_ json: [String: Any]) throws -> ControlNumbers {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(ControlNumbersRecord.self, from: data).numbers
    }

    private let learned = ControlNumbers(
        assignments: [.steps: 20], padBlock: 36, knobBlock: 70, stepButtonBlock: 102)

    /// Unos números recién hechos conocen todos los parámetros de esta app.
    func testFreshNumbersKnowEveryParameter() {
        XCTAssertEqual(learned.knownParameters, Set(TrackParameter.allCases))
    }

    /// Se escribe la lista entera, por clave, también de los que no tienen
    /// control.
    func testTheRecordWritesEveryKnownParameter() throws {
        let json = try dictionary(from: ControlNumbersRecord(learned))
        let keys = try XCTUnwrap(json["parameters"] as? [String])
        XCTAssertEqual(Set(keys), Set(TrackParameter.allCases.map(ControlNumbersRecord.key(for:))))
        XCTAssertTrue(keys.contains("pitch"))
        XCTAssertTrue(keys.contains("harmony"))
    }

    func testTheListSurvivesTheRoundTrip() throws {
        let data = try JSONEncoder().encode(ControlNumbersRecord(learned))
        let returned = try JSONDecoder().decode(ControlNumbersRecord.self, from: data).numbers
        XCTAssertEqual(returned, learned)
    }

    /// **Sin la lista, el fichero es de antes de Pitch y Harmony**: conoce todo
    /// lo demás.
    func testAFileWithoutTheListDidNotKnowPitchNorHarmony() throws {
        var json = try dictionary(from: ControlNumbersRecord(learned))
        json.removeValue(forKey: "parameters")

        XCTAssertEqual(
            try decoded(json).knownParameters,
            Set(TrackParameter.allCases).subtracting([.pitch, .harmony]))
    }

    /// Con la lista, se cree lo que dice; una clave desconocida se descarta,
    /// como en `assignments`.
    func testAListIsTakenAtItsWord() throws {
        var json = try dictionary(from: ControlNumbersRecord(learned))
        json["parameters"] = ["steps", "pitch", "klingon"]

        XCTAssertEqual(try decoded(json).knownParameters, [.steps, .pitch])
    }
}
