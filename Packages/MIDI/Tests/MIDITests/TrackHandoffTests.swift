import Engine
import XCTest
@testable import MIDI

/// Tests de la entrega del Track al hilo del scheduler.
///
/// Es la pieza que el spike dejó pendiente y el mayor riesgo técnico del track:
/// publicar estado nuevo mientras suena, sin lock en el camino de timing.
final class TrackHandoffTests: XCTestCase {

    /// Construye un Track cuyos campos están correlacionados: Steps, Pulses y
    /// Rotate valen todos lo mismo.
    ///
    /// Esa correlación es el detector de lecturas rotas. Copiar un `Track` son
    /// varias palabras de memoria, así que si el escritor pudiera pisar la
    /// ranura que el lector está copiando, el resultado mezclaría campos de dos
    /// publicaciones distintas — y se vería como un Track cuyos tres valores ya
    /// no coinciden.
    private func correlatedTrack(_ value: Int) -> Track {
        let steps = Steps(value)!
        return Track(
            shape: Shape(
                steps: steps,
                pulses: Pulses(value)!,
                rotate: Rotate(value)
            )
        )
    }

    private func assertCorrelated(
        _ track: Track, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(track.shape.pulses.count, track.shape.steps.count, file: file, line: line)
        XCTAssertEqual(track.shape.rotate.amount, track.shape.steps.count, file: file, line: line)
        // Pulses == Steps llena el anillo: todos los Steps disparan.
        for index in 0..<track.shape.steps.count {
            XCTAssertTrue(track.triggers(atStep: index), file: file, line: line)
        }
    }

    // MARK: - Publicar y leer

    func testInitialTrackIsReadableBeforeAnyPublish() {
        let handoff = TrackHandoff(correlatedTrack(4))
        XCTAssertEqual(handoff.load(), correlatedTrack(4))
    }

    func testPublishedTrackIsPickedUpByTheNextLoad() {
        let handoff = TrackHandoff(correlatedTrack(4))
        handoff.publish(correlatedTrack(9))
        XCTAssertEqual(handoff.load(), correlatedTrack(9))
    }

    func testLoadIsRepeatableWithoutConsumingTheValue() {
        let handoff = TrackHandoff(correlatedTrack(7))
        for _ in 0..<1_000 {
            XCTAssertEqual(handoff.load(), correlatedTrack(7))
        }
    }

    func testSuccessivePublicationsAreEachVisible() {
        let handoff = TrackHandoff(correlatedTrack(1))
        for value in Steps.validRange {
            handoff.publish(correlatedTrack(value))
            XCTAssertEqual(handoff.load()?.shape.steps.count, value)
        }
    }

    /// El anillo de ranuras da la vuelta: publicar más veces que ranuras hay no
    /// puede dejar el lector viendo una publicación vieja.
    func testPublishingMoreTimesThanThereAreSlotsStillReadsTheLatest() {
        let handoff = TrackHandoff(correlatedTrack(1))
        for _ in 0..<200 {
            for value in Steps.validRange {
                handoff.publish(correlatedTrack(value))
            }
            XCTAssertEqual(handoff.load()?.shape.steps.count, 16)
        }
    }

    // MARK: - Concurrencia

    /// El test central: publicar desde otro hilo mientras el lector lee no puede
    /// producir un Track con campos de dos publicaciones distintas.
    func testConcurrentPublishNeverYieldsATornTrack() {
        let handoff = TrackHandoff(correlatedTrack(1))
        let writerFinished = expectation(description: "el escritor terminó")

        let writer = Thread {
            for _ in 0..<20_000 {
                for value in Steps.validRange {
                    handoff.publish(self.correlatedTrack(value))
                }
            }
            writerFinished.fulfill()
        }
        writer.qualityOfService = .userInitiated
        writer.start()

        var reads = 0
        var discarded = 0
        while writer.isFinished == false || reads < 10_000 {
            if let track = handoff.load() {
                assertCorrelated(track)
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
        print("TrackHandoff: \(reads) lecturas, \(discarded) descartadas")
    }

    /// Bajo una tasa de publicación realista —un giro de knob es lento
    /// comparado con una ventana de scheduling— no se descarta ninguna lectura.
    func testLoadDoesNotDiscardUnderRealisticPublishRates() {
        let handoff = TrackHandoff(correlatedTrack(3))
        for round in 0..<500 {
            handoff.publish(correlatedTrack((round % 16) + 1))
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
    func testTrackIsATrivialTypeSoCopyingItTakesNoReferenceCounting() {
        XCTAssertTrue(_isPOD(Track.self), "Track dejó de ser trivial: revisar Tonal/Groove")
        XCTAssertTrue(_isPOD(Shape.self))
    }
}

/// Tests del predicado que decide si una lectura es fiable.
///
/// Vive aparte porque comprueba la aritmética, no el comportamiento
/// concurrente: la rama que descarta es inalcanzable en la práctica —el
/// escritor tendría que dar la vuelta al anillo de cuatro ranuras mientras el
/// lector copia unos enteros— y la única forma de verificarla es sobre los
/// números.
final class TrackHandoffSafetyTests: XCTestCase {

    /// Sin publicaciones de por medio, la lectura es fiable.
    func testUnchangedGenerationIsSafe() {
        XCTAssertTrue(TrackHandoff.readIsSafe(latched: 0, observed: 0))
        XCTAssertTrue(TrackHandoff.readIsSafe(latched: 1_000, observed: 1_000))
    }

    /// El escritor puede adelantar hasta dos generaciones sin alcanzar la ranura
    /// latida: con cuatro ranuras, la reescribe al preparar la cuarta.
    func testGenerationMayAdvanceUpToTheSlotDistance() {
        XCTAssertTrue(TrackHandoff.readIsSafe(latched: 10, observed: 11))
        XCTAssertTrue(TrackHandoff.readIsSafe(latched: 10, observed: 12))
    }

    /// A partir de ahí el escritor ya pudo empezar a pisar la ranura, así que la
    /// lectura se descarta.
    func testGenerationBeyondTheSlotDistanceIsDiscarded() {
        XCTAssertFalse(TrackHandoff.readIsSafe(latched: 10, observed: 13))
        XCTAssertFalse(TrackHandoff.readIsSafe(latched: 10, observed: 14))
        XCTAssertFalse(TrackHandoff.readIsSafe(latched: 10, observed: 1_000))
    }

    /// El contador es monótono, pero de 64 bits: si diera la vuelta, la resta
    /// envolvente sigue dando la distancia correcta.
    func testDistanceIsCorrectAcrossCounterWraparound() {
        XCTAssertTrue(TrackHandoff.readIsSafe(latched: .max, observed: .max &+ 1))
        XCTAssertTrue(TrackHandoff.readIsSafe(latched: .max &- 1, observed: .max &+ 1))
        XCTAssertFalse(TrackHandoff.readIsSafe(latched: .max, observed: .max &+ 3))
    }
}
