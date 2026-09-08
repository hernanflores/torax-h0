import XCTest

@testable import Engine

/// Tests de la modulación en disco.
///
/// **Entra por una enmienda del 2026-09-08.** La spec de la rebanada listaba la
/// persistencia entre lo que no existe —se escribió el 2026-09-06, cuando la
/// rebanada 4 estaba por planificar— y `ProjectRecord.swift` ya dejaba dicho lo
/// que pasaría: «las rebanadas 5 y 6 —Note Repeater y Modulation— añaden campos,
/// y el test que enumera las claves esperadas es lo que impide que uno se pierda
/// en silencio». Sin estas dos claves, guardar un Bank perdería `waveform` y
/// `accent` sin decir nada.
///
/// **`schemaVersion` se queda en 1.** `ProjectRecord.validated()` exige igualdad
/// exacta, así que subirla sin migrador dejaría ilegibles los ficheros ya
/// escritos. Un fichero sin las claves nuevas se lee como el estado de antes de
/// la rebanada, que es el criterio 1 aplicado al disco.
final class ModulationRecordTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(5)!)

    private func dictionary(from record: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Las dos claves

    func testTheCycleJSONCarriesTheTwoNewKeys() throws {
        let cycle = Cycle(shape: shape).with(
            modulation: Modulation(waveform: .pulse, accent: Accent(percent: -70)!))
        let json = try dictionary(from: CycleRecord(cycle))

        XCTAssertEqual(json["waveform"] as? String, "pulse")
        XCTAssertEqual(json["accent"] as? Int, -70)
    }

    /// El neutro también se escribe: un `0` explícito dice «sin modulación»,
    /// mientras que una clave ausente solo dice «esto lo escribió otra versión».
    func testTheNeutralModulationIsWrittenToo() throws {
        let json = try dictionary(from: CycleRecord(Cycle(shape: shape)))

        XCTAssertEqual(json["waveform"] as? String, "triangle")
        XCTAssertEqual(json["accent"] as? Int, 0)
    }

    /// **`waveform` se guarda por clave y no por su posición en el `enum`.** El
    /// orden de `allCases` lo manda la rejilla 2×2 de la pantalla (FR11) y puede
    /// querer cambiarse; atar el fichero al índice haría que reordenar la rejilla
    /// cambiara la onda de un Bank ya guardado. Es el criterio de `scale`.
    func testEveryWaveformHasItsOwnStableKey() throws {
        var keys: Set<String> = []
        for waveform in Waveform.allCases {
            let cycle = Cycle(shape: shape).with(modulation: Modulation(waveform: waveform))
            let key = try XCTUnwrap(dictionary(from: CycleRecord(cycle))["waveform"] as? String)
            keys.insert(key)
        }
        XCTAssertEqual(keys, ["saw", "triangle", "sine", "pulse"])
    }

    // MARK: - Vuelve entera

    func testTheModulationSurvivesTheRoundTrip() throws {
        for waveform in Waveform.allCases {
            for percent in [-100, -1, 0, 1, 100] {
                let modulation = Modulation(waveform: waveform, accent: Accent(percent: percent)!)
                let cycle = Cycle(shape: shape).with(modulation: modulation)

                let data = try JSONEncoder().encode(CycleRecord(cycle))
                let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

                XCTAssertEqual(
                    decoded.cycle.modulation, modulation, "\(waveform) accent \(percent)")
            }
        }
    }

    /// Y el Cycle entero vuelve igual: la modulación no se lleva por delante
    /// ninguna de las otras claves.
    func testTheWholeCycleStillSurvivesTheRoundTrip() throws {
        let cycle = Cycle(
            shape: shape,
            pool: PitchPool().inserting(Pitch(48)!).inserting(Pitch(55)!),
            groove: Groove(velocity: Velocity(90)!, sustain: .default, probability: .default),
            channel: Channel(7)!,
            frame: TonalFrame(scale: .lydian, root: Root(5)!),
            noteRepeater: NoteRepeater(repeats: Repeats(4)!),
            modulation: Modulation(waveform: .sine, accent: Accent(percent: 55)!),
            padOctaveShift: -1
        )

        let data = try JSONEncoder().encode(CycleRecord(cycle))
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle, cycle)
    }

    // MARK: - Los ficheros de antes de la rebanada

    /// **Un fichero sin las dos claves se lee como el neutro**, que es
    /// exactamente el estado que ese fichero describía. Es lo que hace que un
    /// Bank guardado antes de la rebanada siga abriendo y sonando igual.
    func testAFileWithoutTheKeysReadsAsTheNeutralModulation() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json.removeValue(forKey: "waveform")
        json.removeValue(forKey: "accent")

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.modulation, .default)
    }

    /// Y no sube la versión del esquema: `validated()` exige igualdad exacta, y
    /// subirla sin migrador dejaría sin abrir los Banks ya escritos.
    func testTheSchemaVersionDoesNotMove() {
        XCTAssertEqual(ProjectRecord.currentSchemaVersion, 1)
    }

    // MARK: - Valores que no deberían existir

    /// Una onda desconocida —un fichero de una versión futura, o tocado a mano—
    /// cae en el default en vez de dejar el Bank sin abrir. Mismo criterio que
    /// `scale`.
    func testAnUnknownWaveformFallsBackToTheDefault() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json["waveform"] = "square"

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.modulation.waveform, .default)
    }

    /// Y un accent fuera de rango también, como el resto de las claves: un byte
    /// malo no es razón para perder un Bank.
    func testAnOutOfRangeAccentFallsBackToTheDefault() throws {
        var json = try dictionary(from: CycleRecord(Cycle(shape: shape)))
        json["accent"] = 900

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CycleRecord.self, from: data)

        XCTAssertEqual(decoded.cycle.modulation.accent, .default)
    }
}
