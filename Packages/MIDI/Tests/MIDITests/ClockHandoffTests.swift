import XCTest

@testable import MIDI

/// Tests de la entrega del reloj externo al hilo del scheduler.
///
/// El estimador vive en el hilo de recepción de CoreMIDI y el scheduler necesita
/// lo que produce. Es el tercer camino sin lock del proyecto —`PatternHandoff`
/// lleva material del control al scheduler, `PlayheadClock` lleva el origen del
/// scheduler a la interfaz— y el único que tiene que entregar **dos** valores
/// que solo valen juntos.
final class ClockHandoffTests: XCTestCase {

    // MARK: - Ida y vuelta

    func testAPublishedReadingComesBackIntact() {
        let handoff = ClockHandoff()
        handoff.publish(
            quarterNoteNanoseconds: 500_000_000, accumulatedCorrectionNanoseconds: -12345)

        XCTAssertEqual(handoff.reading.quarterNoteNanoseconds, 500_000_000)
        XCTAssertEqual(handoff.reading.accumulatedCorrectionNanoseconds, -12345)
    }

    /// Los extremos del rango del producto: la negra de 20 BPM son 3 segundos,
    /// que es el valor grande que tiene que caber; y la corrección acumulada
    /// puede ser negativa durante toda una sesión.
    func testTheExtremesOfTheRangeSurvive() {
        let handoff = ClockHandoff()
        for correction in [Int32.min, -1, 0, 1, Int32.max] {
            handoff.publish(
                quarterNoteNanoseconds: 3_000_000_000, accumulatedCorrectionNanoseconds: correction)

            XCTAssertEqual(handoff.reading.quarterNoteNanoseconds, 3_000_000_000)
            XCTAssertEqual(handoff.reading.accumulatedCorrectionNanoseconds, correction)
        }
    }

    // MARK: - Sin tempo

    /// Antes de que ninguna negra se cierre no hay tempo, y eso es un estado, no
    /// un cero disfrazado: quien lee tiene que poder distinguirlo.
    func testAFreshHandoffIsNotEstablished() {
        XCTAssertFalse(ClockHandoff().reading.isEstablished)
    }

    /// Y volver a ese estado es explícito: lo hace el arranque del transporte.
    func testClearingGoesBackToNotEstablished() {
        let handoff = ClockHandoff()
        handoff.publish(quarterNoteNanoseconds: 500_000_000, accumulatedCorrectionNanoseconds: 7)
        XCTAssertTrue(handoff.reading.isEstablished)

        handoff.clear()

        XCTAssertFalse(handoff.reading.isEstablished)
        XCTAssertEqual(handoff.reading.accumulatedCorrectionNanoseconds, 0)
    }

    // MARK: - Reglas de tiempo real

    /// Lo que cruza es un valor trivial: se construye en el hilo de recepción de
    /// CoreMIDI, que llega cuarenta veces por segundo a 100 BPM y no puede
    /// asignar. Misma red que vigila el snapshot del scheduler.
    func testTheReadingIsATrivialValue() {
        XCTAssertTrue(_isPOD(ClockReading.self))
    }

    // MARK: - El par no se mezcla

    /// **Es la propiedad que justifica el tipo.** El scheduler decide con los dos
    /// valores a la vez: leerlos por separado permitiría combinar el periodo de
    /// antes con la corrección de después, y eso es una rejilla que salta sin
    /// que nada lo explique.
    ///
    /// Los dos se publican correlacionados —la corrección es el periodo dividido
    /// por mil— así que una lectura mezclada se ve como un par que ya no cumple
    /// la relación.
    func testTheTwoValuesAreNeverReadFromDifferentPublications() {
        let handoff = ClockHandoff()
        let writing = expectation(description: "el escritor termina")

        DispatchQueue.global().async {
            for step in 1...20_000 {
                let quarter = UInt32(400_000_000 + step)
                handoff.publish(
                    quarterNoteNanoseconds: quarter,
                    accumulatedCorrectionNanoseconds: Int32(quarter / 1000))
            }
            writing.fulfill()
        }

        for _ in 0..<20_000 {
            let reading = handoff.reading
            guard reading.isEstablished else { continue }
            XCTAssertEqual(
                reading.accumulatedCorrectionNanoseconds,
                Int32(reading.quarterNoteNanoseconds / 1000),
                "El par viene de dos publicaciones distintas")
        }

        wait(for: [writing], timeout: 10)
    }
}
