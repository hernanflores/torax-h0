import XCTest

@testable import Engine

private typealias Pattern = Engine.Pattern

/// Tests de los DTO: que el árbol sobreviva a ida y vuelta, y que el formato en
/// disco **no sea** la disposición en memoria.
///
/// **Las dos mitades importan y son distintas.** La ida y vuelta prueba que no
/// se pierde nada; la comparación contra un JSON literal prueba que el formato
/// está escrito a mano y no sintetizado, que es lo que permite mover un campo de
/// `Cycle` por razones de tiempo real sin romper un fichero guardado.
///
/// `Foundation` se usa aquí y no en `Engine/Sources`: la regla del proyecto es
/// que el **motor** no salga de la stdlib, y `DependencyBoundaryTests` la vigila
/// escaneando `Sources`. Los tests corren en host con XCTest, que ya trae
/// Foundation.
final class RecordRoundTripTests: XCTestCase {

    // MARK: - Ida y vuelta

    /// Un Cycle con todo puesto —Shape girado, pool de varias alturas, Groove
    /// entero, canal, marco tonal y registro de pads— vuelve idéntico.
    func testACycleSurvivesTheRoundTrip() {
        let original = Cycle(
            shape: Shape(
                steps: Steps(12)!, pulses: Pulses(7)!, rotate: Rotate(3), division: .eighth),
            pool: PitchPool().inserting(Pitch(48)!).inserting(Pitch(55)!).inserting(Pitch(60)!),
            groove: Groove(
                velocity: Velocity(100)!,
                sustain: Sustain(percent: 40)!,
                probability: Probability(percent: 75)!,
                timing: Timing(percent: 62)!,
                delay: Delay(percent: -25)!
            ),
            channel: Channel(9)!,
            frame: TonalFrame(scale: .lydian, root: Root(5)!),
            padOctaveShift: -1
        )

        XCTAssertEqual(CycleRecord(original).cycle, original)
    }

    /// **El pool empaquetado en un entero es el caso que hay que ver pasar.**
    /// Las ocho alturas viven en los bits de un `UInt64`, así que si la
    /// traducción se hiciera sobre el almacenamiento en vez de sobre las alturas,
    /// el fichero quedaría atado a esa disposición.
    func testAFullPoolSurvivesTheRoundTrip() {
        var pool = PitchPool()
        for value in [36, 39, 43, 48, 51, 55, 60, 63] {
            pool = pool.inserting(Pitch(value)!)
        }
        XCTAssertEqual(pool.count, PitchPool.capacity)

        let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!), pool: pool)
        let returned = CycleRecord(cycle).cycle

        XCTAssertEqual(returned.pool, pool)
        for index in 0..<PitchPool.capacity {
            XCTAssertEqual(returned.pool.pitch(at: index), pool.pitch(at: index), "hueco \(index)")
        }
    }

    /// Un pool vacío también: es un estado válido, no la ausencia de dato.
    func testAnEmptyPoolSurvivesTheRoundTrip() {
        let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(1)!))
        XCTAssertEqual(CycleRecord(cycle).cycle, cycle)
        XCTAssertTrue(CycleRecord(cycle).cycle.pool.isEmpty)
    }

    /// Los dieciséis Cycles de un Track, cuántos están activos y el cursor de
    /// **edición** vuelven enteros.
    func testATrackSurvivesTheRoundTrip() {
        let base = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!))
        let other = Cycle(
            shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!),
            pool: PitchPool().inserting(Pitch(60)!)
        )
        // **El orden importa y no es casual.** `withActiveCount` copia el Cycle
        // en edición en los huecos que activa —FR3 de la rebanada de Cycles—,
        // así que subir el rango después de escribir el hueco 5 lo pisaría.
        let track = Track(base).withActiveCount(6).replacing(other, at: 4).withEditing(4)

        let returned = TrackRecord(track).track

        XCTAssertEqual(returned.activeCount, 6)
        XCTAssertEqual(returned.editing, 4)
        XCTAssertEqual(returned.cycle(at: 4), other)
        for index in 0..<Track.cycleCount where index != 4 {
            XCTAssertEqual(returned.cycle(at: index), base, "Cycle \(index + 1)")
        }
    }

    /// **El cursor de reproducción NO sobrevive, y es a propósito** (FR8).
    ///
    /// Lo mueve el hilo del scheduler en el límite de vuelta: es estado de
    /// ejecución, no material. Un Pattern entra siempre por el principio de su
    /// desarrollo, así que disparar el break suena igual las dos veces.
    func testThePlaybackCursorIsDeliberatelyNotSaved() {
        let track = Track(Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)))
            .withActiveCount(4)
            .advanced()

        XCTAssertNotEqual(track.cursor, 0, "el test necesita un cursor movido")
        XCTAssertEqual(TrackRecord(track).track.cursor, 0)
    }

    /// Los doce Tracks de un Pattern, cada uno con lo suyo.
    func testAPatternSurvivesTheRoundTrip() {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(
                Cycle(
                    shape: Shape(steps: Steps(index + 4)!, pulses: Pulses(index + 1)!),
                    pool: PitchPool().inserting(Pitch(48 + index)!),
                    channel: Channel(index + 1)!
                ),
                at: index
            )
        }

        XCTAssertEqual(PatternRecord(pattern).pattern, pattern)
    }

    /// Un Bank entero: dieciséis Patterns y su tempo.
    func testABankSurvivesTheRoundTrip() {
        let bank = Bank()
            .replacing(Pattern.initial, at: 0)
            .replacing(Pattern.initial, at: 9)
            .withTempo(Tempo(beatsPerMinute: 174)!)

        let returned = BankRecord(bank).bank

        XCTAssertEqual(returned, bank)
        XCTAssertEqual(returned.tempo, Tempo(beatsPerMinute: 174)!)
    }

    /// Un Project entero: los dieciséis Banks, los tres índices y los ajustes de
    /// sesión.
    func testAProjectSurvivesTheRoundTrip() {
        let project = Project.initial
            .selectingBank(4)
            .selectingPattern(11)
            .selectingTrack(7)
            .withClockSource(.external)
            .remembering(destinationNamed: "Digitakt", sourceNamed: "BeatStep Pro")

        XCTAssertEqual(ProjectRecord(project).project(with: banks(of: project)), project)
    }

    /// Un Project sin hardware recordado también: `nil` es un estado, no un
    /// campo que falte.
    func testAProjectWithNoRememberedHardwareSurvives() {
        let returned = ProjectRecord(Project()).project(with: banks(of: Project()))
        XCTAssertNil(returned.destinationName)
        XCTAssertNil(returned.sourceName)
        XCTAssertEqual(returned, Project())
    }

    /// Las ocho escalas y los doce centros tonales, uno por uno. Es lo que
    /// impide que una escala nueva se guarde como otra por un `switch`
    /// incompleto.
    func testEveryScaleAndRootSurvivesTheRoundTrip() {
        for scale in Scale.allCases {
            for pitchClass in 0..<12 {
                let frame = TonalFrame(scale: scale, root: Root(pitchClass)!)
                let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!), frame: frame)
                XCTAssertEqual(CycleRecord(cycle).cycle.frame, frame, "\(scale) \(pitchClass)")
            }
        }
    }

    // MARK: - El formato no es la memoria

    /// **El JSON se compara contra un literal, campo por campo.**
    ///
    /// Es lo que hace que el formato sea una decisión y no un efecto secundario
    /// de cómo esté escrito el `struct`: si alguien reordena los campos de
    /// `Cycle` —o los renombra, o mete uno en medio— este test sigue pasando, y
    /// si alguien cambia una **clave del fichero**, falla.
    func testTheCycleJSONHasExactlyTheseKeysAndValues() throws {
        let cycle = Cycle(
            shape: Shape(
                steps: Steps(16)!, pulses: Pulses(5)!, rotate: Rotate(2), division: .eighth),
            pool: PitchPool().inserting(Pitch(48)!),
            groove: Groove(
                velocity: Velocity(100)!,
                sustain: Sustain(percent: 100)!,
                probability: Probability(percent: 100)!,
                timing: Timing(percent: 50)!,
                delay: Delay(percent: 0)!
            ),
            channel: Channel(3)!,
            frame: TonalFrame(scale: .minor, root: Root(0)!),
            padOctaveShift: 0
        )

        let json = try dictionary(from: CycleRecord(cycle))

        XCTAssertEqual(json["steps"] as? Int, 16)
        XCTAssertEqual(json["pulses"] as? Int, 5)
        XCTAssertEqual(json["rotate"] as? Int, 2)
        XCTAssertEqual(json["divisionNumerator"] as? Int, 1)
        XCTAssertEqual(json["divisionDenominator"] as? Int, 8)
        XCTAssertEqual(json["pool"] as? [Int], [48])
        XCTAssertEqual(json["velocity"] as? Int, 100)
        XCTAssertEqual(json["sustain"] as? Int, 100)
        XCTAssertEqual(json["probability"] as? Int, 100)
        XCTAssertEqual(json["timing"] as? Int, 50)
        XCTAssertEqual(json["delay"] as? Int, 0)
        XCTAssertEqual(json["channel"] as? Int, 3)
        XCTAssertEqual(json["scale"] as? String, "minor")
        XCTAssertEqual(json["root"] as? Int, 0)
        XCTAssertEqual(json["padOctaveShift"] as? Int, 0)
    }

    /// **Y ni una clave más.** Es la mitad que impide perder un dato en
    /// silencio: cuando las rebanadas 5 y 6 añadan Repeats o waveform al
    /// `Cycle`, este test falla hasta que alguien decida cómo se guarda.
    ///
    /// > **Cumplió las dos veces**, el 2026-09-07 con el Note Repeater y el
    /// > 2026-09-08 con la modulación. Y la segunda dejó ver su límite: este test
    /// > se dispara cuando **sobra** una clave, no cuando **falta** un campo. Lo
    /// > que destapó la pérdida silenciosa de la modulación fue el round trip del
    /// > Cycle entero, no este. Los dos hacen falta.
    func testTheCycleJSONHasNoOtherKeys() throws {
        let expected: Set<String> = [
            "steps", "pulses", "rotate", "divisionNumerator", "divisionDenominator",
            "pool", "velocity", "sustain", "probability", "timing", "delay",
            "channel", "scale", "root", "padOctaveShift",
            // Los cuatro del Note Repeater, desde el 2026-09-07.
            "repeats", "repeatTimeDenominator", "ramp", "pace",
            // Las dos de la modulación, desde el 2026-09-08.
            "waveform", "accent",
            // Pitch, desde el 2026-09-12.
            "pitchOffset",
        ]
        let cycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!))
        XCTAssertEqual(Set(try dictionary(from: CycleRecord(cycle)).keys), expected)
    }

    func testTheTrackJSONHasExactlyTheseKeys() throws {
        let expected: Set<String> = ["cycles", "activeCount", "editing"]
        let track = Track(Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)))
        XCTAssertEqual(Set(try dictionary(from: TrackRecord(track)).keys), expected)
    }

    func testTheBankJSONHasExactlyTheseKeys() throws {
        let expected: Set<String> = ["patterns", "tempo"]
        XCTAssertEqual(Set(try dictionary(from: BankRecord(Bank())).keys), expected)
    }

    func testTheProjectJSONHasExactlyTheseKeys() throws {
        let expected: Set<String> = [
            "schemaVersion", "selectedBank", "selectedPattern", "selectedTrack",
            "clockSource", "destinationName", "sourceName",
        ]
        let record = ProjectRecord(
            Project().remembering(destinationNamed: "a", sourceNamed: "b")
        )
        XCTAssertEqual(Set(try dictionary(from: record).keys), expected)
    }

    /// El nombre de la escala en disco **no es el que enseña la pantalla**. Son
    /// dos vocabularios distintos —uno se lee, otro se guarda— y atarlos haría
    /// que capitalizar un título rompiera ficheros.
    func testTheScaleKeyOnDiskIsNotTheDisplayName() throws {
        let cycle = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(4)!),
            frame: TonalFrame(scale: .minor, root: .c))
        let json = try dictionary(from: CycleRecord(cycle))

        XCTAssertEqual(json["scale"] as? String, "minor")
        XCTAssertEqual(Scale.minor.name, "Minor")
    }

    // MARK: - Helper

    private func dictionary(from record: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(record)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Los dieciséis Banks de un Project, que es lo que la cabecera necesita
    /// para reconstruirlo: en disco viven en ficheros aparte (FR18).
    private func banks(of project: Project) -> [Bank] {
        (0..<Project.bankCount).compactMap { project.bank(at: $0) }
    }
}
