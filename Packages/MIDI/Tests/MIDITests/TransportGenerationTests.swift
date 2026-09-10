import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de la palabra atómica del transporte (FR1, FR2, FR3, FR5).
///
/// **Es la vía de vuelta del transporte**, hermana de la que
/// `AdoptionGenerationTests` cubre para la adopción: el hilo de recepción de
/// CoreMIDI incrementa un contador de generación y publica un flag, y la app los
/// lee desde el `.task` que ya existe. Ni callbacks desde ese hilo, ni
/// temporizadores colgados de vistas — los tres intentos que se revirtieron
/// hicieron lo segundo.
///
/// **El contador y el flag van juntos y se prueban juntos.** Con el contador
/// solo, quien lee sabe que algo pasó pero tiene que volver a `scheduler` para
/// saber qué, y `scheduler` es una propiedad normal que el hilo de recepción
/// reescribe: la carrera que este track existe para no agravar (FR2, NFR2).
///
/// Los tests que arrancan de verdad el bucle del scheduler se agrupan a
/// propósito —igual que en `TransportTests` y `ExternalStartTests`—: cada
/// reproducción crea un hilo de prioridad máxima y acumularlos empeora el flake
/// de CoreMIDI.
final class TransportGenerationTests: XCTestCase {

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [MIDIMessage] = []

        func record(_ message: MIDIMessage, _ hostTime: UInt64) {
            lock.withLock { messages.append(message) }
        }

        var all: [MIDIMessage] { lock.withLock { messages } }
    }

    /// Un transporte con reloj interno, que es el estado de partida de la app.
    private func makeTransport(_ recorder: Recorder) -> Transport {
        let timeline = MusicalTimeline(tempo: Tempo(beatsPerMinute: 300)!, division: .sixteenth)
        return Transport(
            configuration: SchedulerConfiguration(
                timeline: timeline, lookAheadNanoseconds: 20_000_000),
            pattern: Pattern.initial,
            emitter: NoteEmitter(),
            send: recorder.record
        )
    }

    /// El mismo, siguiendo a un maestro externo.
    private func makeFollowingTransport(_ recorder: Recorder) -> Transport {
        let transport = makeTransport(recorder)
        transport.clockSource = .external
        return transport
    }

    // MARK: - Arranca en cero y parado

    func testItStartsAtZeroAndSilent() {
        let transport = makeTransport(Recorder())

        XCTAssertEqual(transport.transportGeneration, 0)
        XCTAssertFalse(transport.isPlaying)
    }

    // MARK: - Una vez por transición, y las cuatro puertas (FR1, FR3)

    /// **Play de la app lo mueve una vez.** No dos, aunque `play()` pase por
    /// `startPlaying(atHostTime:)`: el contador cuenta transiciones, no capas.
    func testAppPlayMovesItExactlyOnce() {
        let transport = makeTransport(Recorder())

        transport.play()
        defer { transport.stop() }

        XCTAssertEqual(transport.transportGeneration, 1)
        XCTAssertTrue(transport.isPlaying)
    }

    /// **Stop de la app lo mueve otra vez**, y deja el flag abajo.
    func testAppStopMovesItAgain() {
        let transport = makeTransport(Recorder())

        transport.play()
        transport.stop()

        XCTAssertEqual(transport.transportGeneration, 2)
        XCTAssertFalse(transport.isPlaying)
    }

    /// **El Start del maestro lo mueve igual que el de la app** (FR3). Un
    /// contador que solo se moviera con el hardware obligaría a mantener dos
    /// caminos de invalidación, y el que se olvidara sería el que falla.
    func testExternalStartMovesIt() {
        let transport = makeFollowingTransport(Recorder())

        transport.receive(.start, atHostTime: HostClock.now())
        defer { transport.stop() }

        XCTAssertEqual(transport.transportGeneration, 1)
        XCTAssertTrue(transport.isPlaying)
    }

    /// **Y el Stop del maestro también.** Es la mitad que el `spec.md` no
    /// contaba y que el diagnóstico del 2026-09-09 encontró en dispositivo: en
    /// t=90 s el maestro paró y la pantalla se quedó creyendo que sonaba.
    func testExternalStopMovesIt() {
        let transport = makeFollowingTransport(Recorder())

        transport.receive(.start, atHostTime: HostClock.now())
        transport.receive(.stop, atHostTime: HostClock.now())

        XCTAssertEqual(transport.transportGeneration, 2)
        XCTAssertFalse(transport.isPlaying)
    }

    /// **Parar lo que ya está parado no lo mueve.** El contador cuenta
    /// transiciones de verdad; si se moviera aquí, el modelo invalidaría la
    /// pantalla por un gesto que no cambió nada.
    func testStoppingWhenAlreadyStoppedDoesNotMoveIt() {
        let transport = makeTransport(Recorder())

        for _ in 0..<10 { transport.stop() }

        XCTAssertEqual(transport.transportGeneration, 0)
        XCTAssertFalse(transport.isPlaying)
    }

    /// **Play sobre lo que ya suena tampoco.** `Transport.play()` muere en su
    /// `guard !isPlaying`, y es exactamente lo que pasaba al pulsar el botón
    /// mientras el maestro mandaba (diagnóstico del 2026-09-09).
    func testPlayingWhenAlreadyPlayingDoesNotMoveIt() {
        let transport = makeTransport(Recorder())

        transport.play()
        for _ in 0..<10 { transport.play() }
        defer { transport.stop() }

        XCTAssertEqual(transport.transportGeneration, 1)
        XCTAssertTrue(transport.isPlaying)
    }

    // MARK: - Un Start sobre algo que ya suena (FR1, FR2)

    /// **Reinicia, y deja el contador consistente con lo que el flag dice.**
    /// Un Start del maestro sobre un transporte que ya suena para y vuelve a
    /// arrancar —es lo que hace el Start de cualquier secuenciador—, así que son
    /// dos transiciones y el flag acaba arriba.
    func testExternalStartWhilePlayingRestartsAndLeavesItConsistent() {
        let transport = makeFollowingTransport(Recorder())

        transport.receive(.start, atHostTime: HostClock.now())
        let afterFirst = transport.transportGeneration

        transport.receive(.start, atHostTime: HostClock.now())
        defer { transport.stop() }

        XCTAssertGreaterThan(transport.transportGeneration, afterFirst, "el reinicio no se publicó")
        XCTAssertTrue(transport.isPlaying, "reinició y el flag dice que no suena")
    }

    // MARK: - El tick no lo mueve (FR5)

    /// **2880 `.timingClock` no lo mueven.** Es el test que impide que alguien
    /// «arregle» el tempo avisando por tick.
    ///
    /// El número no es decorativo: son los ticks de un minuto a 120 bpm con 24
    /// PPQN. Medidos en dispositivo el 2026-09-09, 50,4 por segundo a 124 bpm.
    func testClockTicksDoNotMoveIt() {
        let transport = makeFollowingTransport(Recorder())

        transport.receive(.start, atHostTime: HostClock.now())
        let afterStart = transport.transportGeneration
        defer { transport.stop() }

        var hostTime = HostClock.now()
        for _ in 0..<2880 {
            hostTime &+= HostClock.hostTicks(fromNanoseconds: 20_833_333)
            transport.receive(.timingClock, atHostTime: hostTime)
        }

        XCTAssertEqual(
            transport.transportGeneration, afterStart,
            "el camino del tick publicó algo: son cuarenta y ocho saltos por segundo")
        XCTAssertTrue(transport.isPlaying)
    }

    /// **Y con reloj interno los ticks no llegan siquiera.** Con `Internal` no
    /// se consume nada, así que un maestro puede estar mandando por el mismo
    /// puerto del que llegan los knobs sin tocar el transporte.
    func testClockTicksWithInternalClockDoNotMoveItEither() {
        let transport = makeTransport(Recorder())

        var hostTime = HostClock.now()
        for _ in 0..<500 {
            hostTime &+= HostClock.hostTicks(fromNanoseconds: 20_833_333)
            transport.receive(.timingClock, atHostTime: hostTime)
        }

        XCTAssertEqual(transport.transportGeneration, 0)
    }

    // MARK: - Se lee desde otro hilo (NFR1, NFR2)

    /// **El contador y el flag se leen desde otro hilo sin romper nada**, que es
    /// la única razón por la que son atómicos: los escribe el hilo de recepción
    /// de CoreMIDI y los lee el principal al dibujar.
    ///
    /// Mismo patrón que `AdoptionGenerationTests`: un lado transiciona, el otro
    /// lee, y el contador nunca retrocede.
    func testItIsReadableFromAnotherThreadWhileTransitioning() {
        let transport = makeFollowingTransport(Recorder())
        let transitions = 200

        let done = expectation(description: "transiciones concurrentes")
        done.expectedFulfillmentCount = 2

        DispatchQueue.global().async {
            for _ in 0..<transitions {
                transport.receive(.start, atHostTime: HostClock.now())
                transport.receive(.stop, atHostTime: HostClock.now())
            }
            done.fulfill()
        }

        DispatchQueue.global().async {
            var last: UInt64 = 0
            for _ in 0..<transitions {
                let seen = transport.transportGeneration
                XCTAssertGreaterThanOrEqual(seen, last, "el contador retrocedió")
                last = seen
                _ = transport.isPlaying
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 60)
        transport.stop()

        XCTAssertFalse(transport.isPlaying)
        XCTAssertGreaterThanOrEqual(transport.transportGeneration, UInt64(transitions))
    }

    // MARK: - El flag responde `isPlaying` (FR2, NFR2)

    /// **`isPlaying` sale del flag y no de `scheduler`.** Es lo que elimina la
    /// lectura de una propiedad almacenada que el hilo de recepción reescribe, y
    /// la decisión de NFR2 tomada en la Fase 1.
    ///
    /// Se comprueba por su consecuencia observable: el flag y `isPlaying` dicen
    /// lo mismo en las cuatro puertas. Que la implementación no consulte
    /// `scheduler` lo garantiza el propio cuerpo, que es una línea.
    func testIsPlayingAgreesWithTheFlagAtEveryGate() {
        let transport = makeFollowingTransport(Recorder())

        XCTAssertEqual(transport.isPlaying, transport.isSounding)

        transport.play()
        XCTAssertEqual(transport.isPlaying, transport.isSounding)
        XCTAssertTrue(transport.isSounding)

        transport.stop()
        XCTAssertEqual(transport.isPlaying, transport.isSounding)
        XCTAssertFalse(transport.isSounding)

        transport.receive(.start, atHostTime: HostClock.now())
        XCTAssertEqual(transport.isPlaying, transport.isSounding)
        XCTAssertTrue(transport.isSounding)

        transport.receive(.stop, atHostTime: HostClock.now())
        XCTAssertEqual(transport.isPlaying, transport.isSounding)
        XCTAssertFalse(transport.isSounding)
    }
}
