import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests de la vuelta que sí ocurre en producción: **de bytes a árbol**.
///
/// **`RecordRoundTripTests` no pasa por JSON.** Prueba memoria → record →
/// memoria, que es la traducción, y esa es la mitad barata. La otra mitad —el
/// `Codable` sintetizado decodificando bytes— no la ejecutaba ningún test, y se
/// vio en la cobertura del checkpoint de la Fase 3: `ProjectRecord` al 64,86% de
/// funciones con el 92% de líneas.
///
/// Es la dirección que importa: escribir mal un fichero se nota al releerlo,
/// pero **leer mal uno bien escrito pierde el trabajo del usuario en silencio**.
final class RecordDecodingTests: XCTestCase {

    /// Un Cycle con todo puesto, ida y vuelta **por bytes**.
    func testACycleSurvivesEncodingAndDecoding() throws {
        let cycle = Cycle(
            shape: Shape(
                steps: Steps(12)!, pulses: Pulses(7)!, rotate: Rotate(3), division: .thirtySecond),
            pool: PitchPool().inserting(Pitch(48)!).inserting(Pitch(60)!),
            groove: Groove(
                velocity: Velocity(88)!,
                sustain: Sustain(percent: 30)!,
                probability: Probability(percent: 65)!,
                timing: Timing(percent: 58)!,
                delay: Delay(percent: -40)!
            ),
            channel: Channel(11)!,
            frame: TonalFrame(scale: .hirajoshi, root: Root(9)!),
            padOctaveShift: 2
        )

        XCTAssertEqual(try decoded(CycleRecord(cycle)).cycle, cycle)
    }

    func testATrackSurvivesEncodingAndDecoding() throws {
        let track = Track(Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)))
            .withActiveCount(4)
            .replacing(
                Cycle(
                    shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!),
                    pool: PitchPool().inserting(Pitch(55)!)), at: 2
            )
            .withEditing(2)

        let returned = try decoded(TrackRecord(track)).track

        XCTAssertEqual(returned.activeCount, 4)
        XCTAssertEqual(returned.editing, 2)
        XCTAssertEqual(returned.cycle(at: 2)?.pool.pitch(at: 0), Pitch(55)!)
    }

    /// **Un Bank entero por bytes, con huecos vacíos entre medias.** Es el caso
    /// que junta las dos cosas de la fase: el `null` de la marca tiene que
    /// decodificarse como hueco y no como error.
    func testABankWithGapsSurvivesEncodingAndDecoding() throws {
        let bank = Bank()
            .replacing(Pattern.initial, at: 0)
            .replacing(Pattern.initial, at: 7)
            .withTempo(Tempo(beatsPerMinute: 96)!)

        let returned = try decoded(BankRecord(bank)).bank

        XCTAssertEqual(returned, bank)
        XCTAssertEqual(returned.tempo, Tempo(beatsPerMinute: 96)!)
        XCTAssertEqual(returned.patternsWithMaterial, 2)
    }

    /// El Project entero, que es el fichero que la app abre al arrancar.
    func testTheInitialProjectSurvivesEncodingAndDecoding() throws {
        let project = Project.initial
            .selectingBank(2)
            .selectingPattern(5)
            .selectingTrack(8)
            .withClockSource(.external)
            .remembering(destinationNamed: "Digitakt", sourceNamed: "BeatStep Pro")

        XCTAssertEqual(
            try decoded(ProjectRecord(project)).project(with: banks(of: project)), project)
    }

    /// **Los dos opcionales ausentes se decodifican como `nil`**, no como error.
    /// Es lo que ocurre la primera vez que se abre la app y en cualquier fichero
    /// escrito sin hardware conectado.
    func testAProjectWithNoHardwareSurvivesEncodingAndDecoding() throws {
        let returned = try decoded(ProjectRecord(Project())).project(with: banks(of: Project()))
        XCTAssertNil(returned.destinationName)
        XCTAssertNil(returned.sourceName)
    }

    /// Y decodificar un fichero **escrito a mano**, sin pasar por el encoder:
    /// es la prueba de que las claves del formato son las que la documentación
    /// dice, y no las que el encoder resulte producir.
    func testAHandWrittenCycleJSONDecodes() throws {
        let json = """
            {
              "steps": 16, "pulses": 5, "rotate": 0,
              "divisionNumerator": 1, "divisionDenominator": 16,
              "pool": [48, 55],
              "velocity": 100, "sustain": 100, "probability": 100,
              "timing": 50, "delay": 0,
              "channel": 1, "scale": "dorian", "root": 2, "padOctaveShift": 0
            }
            """
        let record = try JSONDecoder().decode(CycleRecord.self, from: Data(json.utf8))
        let cycle = record.cycle

        XCTAssertEqual(cycle.shape.steps.count, 16)
        XCTAssertEqual(cycle.shape.pulses.count, 5)
        XCTAssertEqual(cycle.pool.count, 2)
        XCTAssertEqual(cycle.frame.scale, .dorian)
        XCTAssertEqual(cycle.frame.root.pitchClass, 2)
    }

    /// **Un valor fuera de rango no impide abrir la app**: cae en su default.
    /// La alternativa —fallar la carga entera— convertiría un byte malo en la
    /// pérdida de un Bank.
    func testOutOfRangeValuesFallBackToTheirDefaults() throws {
        let json = """
            {
              "steps": 999, "pulses": -4, "rotate": 0,
              "divisionNumerator": 0, "divisionDenominator": 0,
              "pool": [48, 500, -1],
              "velocity": 9000, "sustain": -5, "probability": 300,
              "timing": 900, "delay": 5000,
              "channel": 99, "scale": "klingon", "root": 77, "padOctaveShift": 0
            }
            """
        let cycle = try JSONDecoder().decode(CycleRecord.self, from: Data(json.utf8)).cycle

        XCTAssertEqual(cycle.shape.steps.count, 16, "Steps cae en el default")
        XCTAssertEqual(cycle.groove.velocity, .default)
        XCTAssertEqual(cycle.groove.sustain, .default)
        XCTAssertEqual(cycle.channel, .first)
        XCTAssertEqual(cycle.frame.scale, .minor, "una escala desconocida cae en minor")
        XCTAssertEqual(cycle.frame.root, .c)
        XCTAssertEqual(cycle.pool.count, 1, "solo la altura válida entra en el pool")
    }

    /// Un fichero que **no es JSON** falla, y falla como error de decodificación
    /// — que es lo que la Fase 4 distingue de una versión no soportada.
    func testGarbageIsADecodingErrorAndNotASchemaError() {
        let data = Data("esto no es un fichero".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProjectRecord.self, from: data)) { error in
            XCTAssertFalse(error is SchemaError)
        }
    }

    /// Un fichero **bien formado pero de otra versión** llega hasta la
    /// validación, que es la otra mitad de la frase de arriba.
    func testAWellFormedFutureFileDecodesAndThenFailsValidation() throws {
        let record = ProjectRecord(Project(), schemaVersion: 99)
        let returned = try decoded(record)

        XCTAssertEqual(returned.schemaVersion, 99)
        XCTAssertThrowsError(try returned.validated()) { XCTAssertTrue($0 is SchemaError) }
    }

    // MARK: - Helper

    private func decoded<T: Codable>(_ record: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(record))
    }

    /// Los dieciséis Banks de un Project, que es lo que la cabecera necesita
    /// para reconstruirlo: en disco viven en ficheros aparte (FR18).
    private func banks(of project: Project) -> [Bank] {
        (0..<Project.bankCount).compactMap { project.bank(at: $0) }
    }
}
