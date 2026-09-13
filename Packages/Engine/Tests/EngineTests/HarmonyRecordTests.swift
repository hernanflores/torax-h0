import XCTest

@testable import Engine

/// Tests de Harmony en disco (`pitch-harmony_20260912`, FR22, FR23, AC 10).
///
/// **Se guardan los offsets y el cursor, no el knob.** Harmony depende del
/// camino: dos historias con el mismo neto suenan distinto, así que lo único que
/// reproduce lo que sonaba es el estado. Cargar no rehace giros.
///
/// **Un offset por pitch del pool, en el mismo orden que `pool`.** Así el
/// fichero se lee en paralelo: el tercer offset es del tercer pitch. Claves
/// opcionales al leer y escritas siempre, como Pitch y la modulación.
final class HarmonyRecordTests: XCTestCase {

    private func dictionary(from record: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decoded(_ json: [String: Any]) throws -> Cycle {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(CycleRecord.self, from: data).cycle
    }

    /// C4 E4 G4 en Do mayor con Pitch +1 y tres clics y uno inverso: offsets
    /// 0 1 1, cursor en el segundo.
    private var moved: Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: PitchPool().inserting(Pitch(60)!).inserting(Pitch(64)!).inserting(Pitch(67)!),
            frame: TonalFrame(scale: .major, root: .c),
            pitchOffset: PitchOffset(1)!
        ).applying(3, to: .harmony).applying(-1, to: .harmony)
    }

    // MARK: - Las claves

    func testTheCycleJSONCarriesOffsetsAndCursor() throws {
        let json = try dictionary(from: CycleRecord(moved))
        XCTAssertEqual(json["harmonyOffsets"] as? [Int], [0, 1, 1])
        XCTAssertEqual(json["harmonyCursor"] as? Int, 1)
    }

    /// El estado limpio también se escribe: un offset por pitch, todos a 0.
    func testCleanHarmonyIsWrittenToo() throws {
        let clean = moved.with(harmony: .clean)
        let json = try dictionary(from: CycleRecord(clean))
        XCTAssertEqual(json["harmonyOffsets"] as? [Int], [0, 0, 0])
        XCTAssertEqual(json["harmonyCursor"] as? Int, 0)
    }

    // MARK: - Ida y vuelta

    /// Guardar y cargar reproduce lo que suena sin rehacer giros (AC 10).
    func testHarmonySurvivesTheRoundTrip() throws {
        let data = try JSONEncoder().encode(CycleRecord(moved))
        let returned = try JSONDecoder().decode(CycleRecord.self, from: data).cycle

        XCTAssertEqual(returned, moved)
        XCTAssertEqual(returned.soundingPool, moved.soundingPool)
        XCTAssertEqual(
            returned.applying(1, to: .harmony), moved.applying(1, to: .harmony),
            "el cursor no volvió: el siguiente clic mueve otro pitch")
    }

    // MARK: - Ficheros de antes, y ficheros malos

    /// Un fichero sin las claves se lee con Harmony limpio.
    func testAFileWithoutTheKeysReadsAsCleanHarmony() throws {
        var json = try dictionary(from: CycleRecord(moved))
        json.removeValue(forKey: "harmonyOffsets")
        json.removeValue(forKey: "harmonyCursor")

        XCTAssertEqual(try decoded(json).harmony, .clean)
    }

    /// **Un offset imposible o un cursor fuera del pool limpian Harmony entero.**
    /// Medio estado sonaría a notas que nadie eligió; el limpio es lo que el
    /// fichero puede prometer.
    func testAnImpossibleStateFallsBackToClean() throws {
        var badOffset = try dictionary(from: CycleRecord(moved))
        badOffset["harmonyOffsets"] = [0, 900, 1]
        XCTAssertEqual(try decoded(badOffset).harmony, .clean)

        var badCursor = try dictionary(from: CycleRecord(moved))
        badCursor["harmonyCursor"] = 8
        XCTAssertEqual(try decoded(badCursor).harmony, .clean)
    }

    /// Offsets de más —un pool que se tocó a mano— se ignoran; de menos, cuentan
    /// como 0.
    func testExtraOffsetsAreIgnoredAndMissingOnesAreZero() throws {
        var extra = try dictionary(from: CycleRecord(moved))
        extra["harmonyOffsets"] = [0, 1, 1, 5]
        XCTAssertEqual(try decoded(extra).harmony, moved.harmony)

        var short = try dictionary(from: CycleRecord(moved))
        short["harmonyOffsets"] = [2]
        let harmony = try decoded(short).harmony
        XCTAssertEqual((0..<3).map { harmony.offset(at: $0) }, [2, 0, 0])
    }

    func testTheSchemaVersionDoesNotMove() {
        XCTAssertEqual(ProjectRecord.currentSchemaVersion, 1)
    }

    // MARK: - Copias

    /// Copiar un Pattern arrastra el estado exacto (FR23).
    func testCopyingAPatternCarriesHarmony() throws {
        let track = try XCTUnwrap(Pattern.initial.track(at: 0)).replacing(moved, at: 0)
        let pattern = Pattern.initial.replacing(track, at: 0)
        let copied = Bank().replacing(pattern, at: 0).copyingPattern(from: 0, to: 3)

        XCTAssertEqual(copied.pattern(at: 3)?.track(at: 0)?.cycle(at: 0)?.harmony, moved.harmony)
    }
}
