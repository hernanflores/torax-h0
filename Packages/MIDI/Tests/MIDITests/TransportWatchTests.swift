import XCTest

@testable import MIDI

/// Tests de la vía de vuelta del transporte (FR6, FR7).
///
/// **Es un poll y no un callback**, por la misma razón que `PendingAdoption`: el
/// hilo de recepción de CoreMIDI publica una palabra atómica al arrancar y al
/// parar, y llamar hacia el modelo desde ahí sería trabajo en el camino de
/// tiempo real.
///
/// **La decisión vive aquí y no en `App`.** `App` no se mide (`workflow.md`), y
/// «¿cambió algo desde la última vez?» tiene casos límite —dos transiciones
/// entre dos cuadros, el arranque en frío— que merecen prueba.
final class TransportWatchTests: XCTestCase {

    // MARK: - Sin cambios no pasa nada (FR7)

    /// **Lo que ocurre en casi todos los cuadros.** Una lectura atómica, una
    /// comparación de enteros, y nada más: sin esto, la pantalla se invalidaría
    /// sesenta veces por segundo para decir lo mismo.
    func testItReportsNothingWhenTheGenerationDidNotMove() {
        let watch = TransportWatch()

        XCTAssertNil(watch.changed(generation: 0, isSounding: false))
    }

    /// Un segundo de cuadros sobre un transporte que no se mueve: un reporte
    /// —el del arranque en frío— y cincuenta y nueve silencios.
    func testItKeepsReportingNothingWhileTheGenerationStaysPut() {
        let watch = TransportWatch()

        XCTAssertEqual(watch.changed(generation: 7, isSounding: true), true)

        for _ in 0..<59 {
            XCTAssertNil(watch.changed(generation: 7, isSounding: true))
        }
    }

    // MARK: - El primer cuadro (FR7)

    /// **Un transporte que ya suena al primer poll se reporta.** Es el arranque
    /// en frío: el contador vale más que el cero con el que nace el observador,
    /// así que hay algo que la pantalla todavía no sabe.
    func testItReportsOnTheFirstPollWhenTheGenerationAlreadyMoved() {
        let watch = TransportWatch()

        XCTAssertEqual(watch.changed(generation: 1, isSounding: true), true)
    }

    /// Y un transporte parado y quieto al arrancar no reporta nada: el contador
    /// coincide con el que el observador trae de fábrica.
    func testItReportsNothingOnTheFirstPollOfAFreshTransport() {
        let watch = TransportWatch()

        XCTAssertNil(watch.changed(generation: 0, isSounding: false))
    }

    // MARK: - Con cambios reporta el estado, no el contador (FR6)

    /// **Lo que se devuelve es el estado, no cuántas veces cambió.** Quien lo
    /// lee quiere saber si suena; el contador solo sirve para saber que hay algo
    /// nuevo que mirar.
    func testItReportsSoundingWhenTheTransportStarted() {
        let watch = TransportWatch()
        _ = watch.changed(generation: 0, isSounding: false)

        XCTAssertEqual(watch.changed(generation: 1, isSounding: true), true)
    }

    func testItReportsSilentWhenTheTransportStopped() {
        let watch = TransportWatch()
        _ = watch.changed(generation: 1, isSounding: true)

        XCTAssertEqual(watch.changed(generation: 2, isSounding: false), false)
    }

    /// **Reportar consume el cambio.** El siguiente poll sin nada nuevo no
    /// vuelve a reportar, o el modelo invalidaría la pantalla en cada cuadro
    /// después de cada transición.
    func testReportingConsumesTheChange() {
        let watch = TransportWatch()

        XCTAssertEqual(watch.changed(generation: 1, isSounding: true), true)
        XCTAssertNil(watch.changed(generation: 1, isSounding: true))
    }

    // MARK: - Dos transiciones entre dos cuadros (FR11)

    /// **Manda el estado final, no el recorrido.** Arrancar y parar dentro de
    /// los mismos 16 ms deja el contador en dos y el flag abajo: lo que la
    /// pantalla tiene que enseñar es que no suena. El estado intermedio no se
    /// perdió por un fallo — nunca fue visible, y FR11 ya declara que la
    /// pantalla puede ir un cuadro por detrás.
    func testItReportsTheFinalStateWhenTwoTransitionsFitInOneFrame() {
        let watch = TransportWatch()
        _ = watch.changed(generation: 0, isSounding: false)

        XCTAssertEqual(watch.changed(generation: 2, isSounding: false), false)
    }

    /// **El caso simétrico, y el que justifica que haya un contador.** Parar y
    /// volver a arrancar entre dos cuadros deja el flag donde estaba: mirar solo
    /// el flag no vería nada, y sin embargo la rejilla es otra y la pantalla
    /// tiene motivos para repintarse. Es lo que hace un Start del maestro sobre
    /// algo que ya suena. Por eso FR1 pide un contador y no un booleano.
    func testItReportsARestartEvenThoughTheStateIsUnchanged() {
        let watch = TransportWatch()
        _ = watch.changed(generation: 1, isSounding: true)

        XCTAssertEqual(watch.changed(generation: 3, isSounding: true), true)
    }

    // MARK: - Una sesión entera

    /// La secuencia del diagnóstico del 2026-09-09, en pequeño: arranque del
    /// maestro, parada del maestro, arranque otra vez. Tres reportes y ni uno
    /// más, con los cuadros vacíos de por medio que hay de verdad.
    func testATypicalSessionReportsOncePerTransition() {
        let watch = TransportWatch()
        var reports: [Bool] = []

        func poll(_ generation: UInt64, _ isSounding: Bool) {
            if let state = watch.changed(generation: generation, isSounding: isSounding) {
                reports.append(state)
            }
        }

        for _ in 0..<10 { poll(0, false) }
        poll(1, true)
        for _ in 0..<10 { poll(1, true) }
        poll(2, false)
        for _ in 0..<10 { poll(2, false) }
        poll(3, true)
        for _ in 0..<10 { poll(3, true) }

        XCTAssertEqual(reports, [true, false, true])
    }
}
