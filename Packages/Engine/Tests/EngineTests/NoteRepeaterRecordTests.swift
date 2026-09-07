import XCTest

@testable import Engine

/// Tests de los cuatro parámetros del Note Repeater en disco.
///
/// **Entra por una enmienda del 2026-09-07.** El plan de la rebanada daba la
/// persistencia por inexistente —se escribió el 2026-09-06, cuando la rebanada 4
/// estaba por planificar— y `ProjectRecord.swift` ya dejaba dicho lo que pasaría:
/// «añadir un parámetro al `Cycle` tiene que romper un test». Sin estas cuatro
/// claves, guardar un Bank perdería Repeats, Time, Ramp y Pace en silencio.
///
/// **`schemaVersion` se queda en 1.** `ProjectRecord.validated()` exige igualdad
/// exacta, así que subirla sin migrador dejaría ilegibles los ficheros ya
/// escritos. Un fichero sin las claves nuevas se lee como el estado de antes de
/// la rebanada, que es la promesa de FR16 aplicada al disco.
final class NoteRepeaterRecordTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(5)!)

    private func dictionary(from record: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Las cuatro claves

    func testTheCycleJSONCarriesTheFourNewKeys() throws {
        let cycle = Cycle(shape: shape).with(
            noteRepeater: NoteRepeater(
                repeats: Repeats(6)!,
                time: RepeatTime.ordered.last!,
                ramp: Ramp(percent: -70)!,
                pace: Pace(percent: 35)!
            ))
        let json = try dictionary(from: CycleRecord(cycle))

        XCTAssertEqual(json["repeats"] as? Int, 6)
        XCTAssertEqual(json["repeatTimeDenominator"] as? Int, 128)
        XCTAssertEqual(json["ramp"] as? Int, -70)
        XCTAssertEqual(json["pace"] as? Int, 35)
    }

    /// El neutro también se escribe: un `0` explícito dice «sin repeticiones»,
    /// mientras que una clave ausente solo dice «esto lo escribió otra versión».
    func testTheNeutralRepeaterIsWrittenToo() throws {
        let json = try dictionary(from: CycleRecord(Cycle(shape: shape)))

        XCTAssertEqual(json["repeats"] as? Int, 0)
        XCTAssertEqual(json["repeatTimeDenominator"] as? Int, 32)
        XCTAssertEqual(json["ramp"] as? Int, 0)
        XCTAssertEqual(json["pace"] as? Int, 0)
    }

    // MARK: - Vuelve entero

    func testTheFourSurviveTheRoundTrip() throws {
        let repeater = NoteRepeater(
            repeats: Repeats(3)!,
            time: RepeatTime.ordered.first!,
            ramp: Ramp(percent: 100)!,
            pace: Pace(percent: -100)!
        )
        let cycle = Cycle(shape: shape).with(noteRepeater: repeater)

        let data = try JSONEncoder().encode(CycleRecord(cycle))
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.noteRepeater, repeater)
        XCTAssertEqual(decoded.cycle, cycle)
    }

    /// Las nueve fracciones vuelven todas, tresillos incluidos.
    func testEveryTimeSurvivesTheRoundTrip() throws {
        for time in RepeatTime.ordered {
            let cycle = Cycle(shape: shape).with(noteRepeater: NoteRepeater(time: time))
            let data = try JSONEncoder().encode(CycleRecord(cycle))
            let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)
            XCTAssertEqual(decoded.cycle.noteRepeater.time, time, "\(time)")
        }
    }

    // MARK: - Un fichero de antes de la rebanada

    /// **La promesa de FR16, aplicada al disco.** Un Bank escrito antes de la
    /// rebanada no lleva las cuatro claves, y se lee como el estado de entonces:
    /// Repeats 0, Time 1/32, Ramp 0, Pace 0.
    func testAFileWithoutTheNewKeysReadsAsTheNeutralRepeater() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        for key in ["repeats", "repeatTimeDenominator", "ramp", "pace"] {
            json.removeValue(forKey: key)
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.noteRepeater, NoteRepeater.default)
    }

    /// Y la versión de esquema no se mueve: los ficheros ya escritos siguen
    /// abriendo.
    func testTheSchemaVersionStaysAtOne() {
        XCTAssertEqual(ProjectRecord.currentSchemaVersion, 1)
    }

    // MARK: - Basura en el fichero

    /// Un valor fuera de rango cae en su default en vez de reventar, con el
    /// mismo criterio que el resto de las claves: un byte malo no puede costar
    /// un Bank.
    func testOutOfRangeValuesFallBackToTheirDefaults() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json["repeats"] = 900
        json["repeatTimeDenominator"] = 7
        json["ramp"] = -4000
        json["pace"] = 4000

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.noteRepeater, NoteRepeater.default)
    }
}
