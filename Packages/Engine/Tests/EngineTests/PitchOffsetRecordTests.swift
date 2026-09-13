import XCTest

@testable import Engine

/// Tests de Pitch en disco (`pitch-harmony_20260912`, FR22, FR23).
///
/// **Mismo criterio que la modulación y el Note Repeater.** La clave es opcional
/// al leer y se escribe siempre: un fichero anterior al track la decodifica como
/// `nil` y se lee sin transponer, que es exactamente lo que describía.
/// `schemaVersion` se queda en 1.
///
/// **Se guarda el offset, no el pool que suena.** El pool que suena se deriva al
/// construir el Cycle; guardarlo sería tener dos fuentes de lo mismo, y la
/// segunda podría contradecir a la primera al tocar el fichero a mano.
final class PitchOffsetRecordTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(5)!)

    private func dictionary(from record: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decoded(_ json: [String: Any]) throws -> Cycle {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(CycleRecord.self, from: data).cycle
    }

    private var transposed: Cycle {
        Cycle(
            shape: shape,
            pool: PitchPool().inserting(Pitch(60)!).inserting(Pitch(64)!),
            frame: TonalFrame(scale: .major, root: .c),
            pitchOffset: PitchOffset(-3)!)
    }

    // MARK: - La clave

    func testTheCycleJSONCarriesThePitchOffset() throws {
        XCTAssertEqual(try dictionary(from: CycleRecord(transposed))["pitchOffset"] as? Int, -3)
    }

    /// **El neutro también se escribe**: un `0` explícito dice «sin transponer».
    func testTheNeutralOffsetIsWrittenToo() throws {
        XCTAssertEqual(
            try dictionary(from: CycleRecord(Cycle(shape: shape)))["pitchOffset"] as? Int, 0)
    }

    /// **No se guarda el pool que suena**: el pool base sigue siendo el que está
    /// en `pool`.
    func testThePoolKeyIsTheBasePool() throws {
        XCTAssertEqual(try dictionary(from: CycleRecord(transposed))["pool"] as? [Int], [60, 64])
    }

    // MARK: - Ida y vuelta

    /// Guardar y cargar reproduce lo que suena sin rehacer giros (AC 10).
    func testTheOffsetSurvivesTheRoundTrip() throws {
        let data = try JSONEncoder().encode(CycleRecord(transposed))
        let returned = try JSONDecoder().decode(CycleRecord.self, from: data).cycle

        XCTAssertEqual(returned, transposed)
        XCTAssertEqual(returned.soundingPool, transposed.soundingPool)
    }

    // MARK: - Ficheros de antes, y ficheros malos

    /// Un fichero sin la clave se lee sin transponer.
    func testAFileWithoutTheKeyReadsAsNoTransposition() throws {
        var json = try dictionary(from: CycleRecord(transposed))
        json.removeValue(forKey: "pitchOffset")

        let cycle = try decoded(json)
        XCTAssertEqual(cycle.pitchOffset, .zero)
        XCTAssertEqual(cycle.soundingPool, cycle.pool)
    }

    /// Un offset fuera de ±28 cae en el neutro, como el resto de las claves.
    func testAnOutOfRangeOffsetFallsBackToZero() throws {
        var json = try dictionary(from: CycleRecord(transposed))
        json["pitchOffset"] = 900

        XCTAssertEqual(try decoded(json).pitchOffset, .zero)
    }

    func testTheSchemaVersionDoesNotMove() {
        XCTAssertEqual(ProjectRecord.currentSchemaVersion, 1)
    }

    // MARK: - Copias

    /// Copiar un Pattern arrastra el offset exacto (FR23).
    func testCopyingAPatternCarriesTheOffset() throws {
        let track = try XCTUnwrap(Pattern.initial.track(at: 0)).replacing(transposed, at: 0)
        let pattern = Pattern.initial.replacing(track, at: 0)
        let copied = Bank().replacing(pattern, at: 0).copyingPattern(from: 0, to: 3)

        XCTAssertEqual(
            copied.pattern(at: 3)?.track(at: 0)?.cycle(at: 0)?.pitchOffset, PitchOffset(-3))
    }
}
