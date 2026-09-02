import Engine
import XCTest
@testable import MIDI

/// **`Pattern` a secas es ambiguo en un target de test**: corren en macOS y
/// XCTest arrastra `ApplicationServices`, que trae un `Pattern` de Quickdraw.
private typealias Pattern = Engine.Pattern

/// Tests de la entrega del material al hilo del scheduler.
///
/// Es la pieza que el spike dejó pendiente y el mayor riesgo técnico del
/// proyecto: publicar estado nuevo mientras suena, sin lock en el camino de
/// timing. **Desde la v2 lo que se publica son los dieciséis Tracks**, así que
/// la ranura es dieciséis veces mayor y la ventana para una lectura mezclada,
/// dieciséis veces más ancha.
final class PatternHandoffTests: XCTestCase {

    /// Construye un Track cuyos campos están correlacionados: Steps, Pulses y
    /// Rotate valen todos lo mismo.
    ///
    /// Esa correlación es el detector de lecturas rotas. Copiar un `Track` son
    /// varias palabras de memoria, así que si el escritor pudiera pisar la
    /// ranura que el lector está copiando, el resultado mezclaría campos de dos
    /// publicaciones distintas — y se vería como un Track cuyos tres valores ya
    /// no coinciden.
    private func correlatedTrack(_ value: Int) -> Cycle {
        let steps = Steps(value)!
        return Cycle(
            shape: Shape(
                steps: steps,
                pulses: Pulses(value)!,
                rotate: Rotate(value)
            )
        )
    }

    /// Un Pattern cuyos dieciséis Tracks están correlacionados con el mismo
    /// valor.
    ///
    /// **Es el detector de lecturas mezcladas, ampliado.** Con un solo Track la
    /// mezcla se veía entre sus campos; con dieciséis, también entre Tracks: una
    /// lectura rota traería el Track 3 de una publicación y el 11 de otra.
    private func correlatedPattern(_ value: Int) -> Pattern {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(correlatedTrack(value), at: index)
        }
        return pattern
    }

    private func assertCorrelated(
        _ pattern: Pattern, file: StaticString = #filePath, line: UInt = #line
    ) {
        let first = pattern.cycle(at: 0)!.shape.steps.count
        for index in 0..<Pattern.trackCount {
            let track = pattern.cycle(at: index)!
            // Entre Tracks: los dieciséis vienen de la misma publicación.
            XCTAssertEqual(track.shape.steps.count, first, file: file, line: line)
            // Y dentro de cada uno, entre campos.
            assertCorrelated(track, file: file, line: line)
        }
    }

    private func assertCorrelated(
        _ track: Cycle, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(track.shape.pulses.count, track.shape.steps.count, file: file, line: line)
        XCTAssertEqual(track.shape.rotate.amount, track.shape.steps.count, file: file, line: line)
        // Pulses == Steps llena el anillo: todos los Steps disparan.
        for index in 0..<track.shape.steps.count {
            XCTAssertTrue(track.triggers(atStep: index), file: file, line: line)
        }
    }

    // MARK: - Publicar y leer

    func testInitialPatternIsReadableBeforeAnyPublish() {
        let handoff = PatternHandoff(correlatedPattern(4))
        XCTAssertEqual(handoff.load(), correlatedPattern(4))
    }

    func testPublishedPatternIsPickedUpByTheNextLoad() {
        let handoff = PatternHandoff(correlatedPattern(4))
        handoff.publish(correlatedPattern(9))
        XCTAssertEqual(handoff.load(), correlatedPattern(9))
    }

    func testLoadIsRepeatableWithoutConsumingTheValue() {
        let handoff = PatternHandoff(correlatedPattern(7))
        for _ in 0..<1_000 {
            XCTAssertEqual(handoff.load(), correlatedPattern(7))
        }
    }

    func testSuccessivePublicationsAreEachVisible() {
        let handoff = PatternHandoff(correlatedPattern(1))
        for value in Steps.validRange {
            handoff.publish(correlatedPattern(value))
            XCTAssertEqual(handoff.load()?.cycle(at: 0)?.shape.steps.count, value)
        }
    }

    /// **Los dieciséis Tracks llegan enteros, no solo el primero.** Es lo que
    /// distingue publicar un Pattern de publicar un Track con quince pasajeros
    /// que nadie mira.
    func testEveryTrackSurvivesThePublication() {
        var published = Pattern()
        for index in 0..<Pattern.trackCount {
            published = published.replacing(correlatedTrack(index + 1), at: index)
        }

        let handoff = PatternHandoff(Pattern())
        handoff.publish(published)

        let read = handoff.load()
        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(
                read?.cycle(at: index)?.shape.steps.count, index + 1, "Track \(index + 1)")
        }
    }

    /// El anillo de ranuras da la vuelta: publicar más veces que ranuras hay no
    /// puede dejar el lector viendo una publicación vieja.
    func testPublishingMoreTimesThanThereAreSlotsStillReadsTheLatest() {
        let handoff = PatternHandoff(correlatedPattern(1))
        for _ in 0..<200 {
            for value in Steps.validRange {
                handoff.publish(correlatedPattern(value))
            }
            XCTAssertEqual(handoff.load()?.cycle(at: 0)?.shape.steps.count, 16)
        }
    }

    // MARK: - Concurrencia

    /// El test central: publicar desde otro hilo mientras el lector lee no puede
    /// producir un Track con campos de dos publicaciones distintas.
    func testConcurrentPublishNeverYieldsATornTrack() {
        let handoff = PatternHandoff(correlatedPattern(1))
        let writerFinished = expectation(description: "el escritor terminó")

        // Menos vueltas que con un Track solo: cada publicación copia dieciséis
        // veces más, y lo que se mide es la mezcla, no el rendimiento.
        let writer = Thread {
            for _ in 0..<2_000 {
                for value in Steps.validRange {
                    handoff.publish(self.correlatedPattern(value))
                }
            }
            writerFinished.fulfill()
        }
        // **La pila por defecto de un `Thread` secundario son 512 KB, y con
        // Cycles ya no bastan.** Construir un Pattern deja varios temporales de
        // 37 KB vivos en el mismo marco, así que este bucle desbordaba con la
        // pila por defecto: medido el 2026-09-02, revienta con 512 KB y pasa con
        // 1 MB. El hilo del scheduler lleva la misma reserva, y por la misma
        // razón — ver `SchedulerThread.start()`.
        writer.stackSize = 1 << 20
        writer.qualityOfService = .userInitiated
        writer.start()

        var reads = 0
        var discarded = 0
        while writer.isFinished == false || reads < 10_000 {
            if let pattern = handoff.load() {
                assertCorrelated(pattern)
            } else {
                discarded += 1
            }
            reads += 1
            if reads > 2_000_000 { break }
        }

        wait(for: [writerFinished], timeout: 60)
        XCTAssertGreaterThan(reads, 10_000)
        // Descartar es legítimo y esperado bajo esta tasa de escritura absurda;
        // lo que no es aceptable es devolver un valor mezclado.
        print("PatternHandoff: \(reads) lecturas, \(discarded) descartadas")
    }

    /// Bajo una tasa de publicación realista —un giro de knob es lento
    /// comparado con una ventana de scheduling— no se descarta ninguna lectura.
    func testLoadDoesNotDiscardUnderRealisticPublishRates() {
        let handoff = PatternHandoff(correlatedPattern(3))
        for round in 0..<500 {
            handoff.publish(correlatedPattern((round % 16) + 1))
            XCTAssertNotNil(handoff.load(), "descartó una lectura sin contención")
        }
    }

    // MARK: - Requisitos de tiempo real

    /// El Track tiene que poder copiarse sin tocar el conteo de referencias: un
    /// `retain`/`release` en el hilo del scheduler es exactamente lo que las
    /// reglas de tiempo real prohíben.
    ///
    /// Es la restricción que hay que preservar cuando lleguen Tonal y Groove: el
    /// pool de pitches tiene que ser almacenamiento inline, no un `Array`.
    func testTheSnapshotIsATrivialTypeSoCopyingItTakesNoReferenceCounting() {
        XCTAssertTrue(_isPOD(Pattern.self), "Pattern dejó de ser trivial")
        XCTAssertTrue(_isPOD(Cycle.self), "Cycle dejó de ser trivial: revisar Tonal/Groove")
        XCTAssertTrue(_isPOD(Shape.self))
    }

    /// **El número que la fase 2 existía para conocer**: lo que el hilo del
    /// scheduler copia en cada ventana. Se fija aquí para que un crecimiento
    /// futuro del modelo se vea como un cambio, y no como una sorpresa medida
    /// tarde.
    ///
    /// > **El detector saltó, y funcionó como se esperaba.** La cota de 4 KB era
    /// > de la rebanada 1 de la v2, y Cycles la rompió: el snapshot pasó a
    /// > 37 120 bytes. Que saltara obligó a volver a tomar la decisión con el
    /// > número delante, que es exactamente para lo que estaba puesta — y se
    /// > tomó **antes** de construir nada, en la Fase 1 del track
    /// > `cycles_20260901`: ~870 ns por `load()`, el 0,0044% de la ventana.
    /// >
    /// > La cota nueva es 64 KB, y sigue sin ser un umbral de rendimiento sino
    /// > un detector de cambio de orden. El siguiente escalón de la Pre Spec
    /// > —dieciséis Patterns por Bank— **no** pasa por aquí: eso es persistencia,
    /// > y lo que cruza al hilo del scheduler sigue siendo un Pattern.
    func testTheSnapshotIsSixteenTracksWideAndNothingMore() {
        XCTAssertEqual(MemoryLayout<Pattern>.size, MemoryLayout<Track>.size * 16)
        XCTAssertLessThan(MemoryLayout<Pattern>.size, 65_536, "el snapshot creció de orden")
    }
}

/// Tests del predicado que decide si una lectura es fiable.
///
/// Vive aparte porque comprueba la aritmética, no el comportamiento
/// concurrente: la rama que descarta es inalcanzable en la práctica —el
/// escritor tendría que dar la vuelta al anillo de cuatro ranuras mientras el
/// lector copia unos enteros— y la única forma de verificarla es sobre los
/// números.
final class PatternHandoffSafetyTests: XCTestCase {

    /// Sin publicaciones de por medio, la lectura es fiable.
    func testUnchangedGenerationIsSafe() {
        XCTAssertTrue(PatternHandoff.readIsSafe(latched: 0, observed: 0))
        XCTAssertTrue(PatternHandoff.readIsSafe(latched: 1_000, observed: 1_000))
    }

    /// El escritor puede adelantar hasta dos generaciones sin alcanzar la ranura
    /// latida: con cuatro ranuras, la reescribe al preparar la cuarta.
    func testGenerationMayAdvanceUpToTheSlotDistance() {
        XCTAssertTrue(PatternHandoff.readIsSafe(latched: 10, observed: 11))
        XCTAssertTrue(PatternHandoff.readIsSafe(latched: 10, observed: 12))
    }

    /// A partir de ahí el escritor ya pudo empezar a pisar la ranura, así que la
    /// lectura se descarta.
    func testGenerationBeyondTheSlotDistanceIsDiscarded() {
        XCTAssertFalse(PatternHandoff.readIsSafe(latched: 10, observed: 13))
        XCTAssertFalse(PatternHandoff.readIsSafe(latched: 10, observed: 14))
        XCTAssertFalse(PatternHandoff.readIsSafe(latched: 10, observed: 1_000))
    }

    /// El contador es monótono, pero de 64 bits: si diera la vuelta, la resta
    /// envolvente sigue dando la distancia correcta.
    func testDistanceIsCorrectAcrossCounterWraparound() {
        XCTAssertTrue(PatternHandoff.readIsSafe(latched: .max, observed: .max &+ 1))
        XCTAssertTrue(PatternHandoff.readIsSafe(latched: .max &- 1, observed: .max &+ 1))
        XCTAssertFalse(PatternHandoff.readIsSafe(latched: .max, observed: .max &+ 3))
    }
}
