import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del gesto de Temp en el controlador (FR1, FR7, FR9).
///
/// **Mantener el step button 13 y girar un knob cambia lo que suena sin
/// escribirlo en el Pattern**; al soltar, los valores anteriores vuelven. Es el
/// tercer modificador y no inventa mecánica: el 15 y el 16 ya son solo y mute
/// con el mismo 127 al pulsar y 0 al soltar, y del 13 al 16 no hay Track detrás
/// desde que el Pattern bajó a doce.
///
/// **Sin temporizador, y eso es el punto.** «Mantenido» es estado de mensajes,
/// así que el gesto entero se prueba con mensajes.
final class TempModifierInputTests: XCTestCase {

    /// Lo que se publicó, en orden.
    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var patterns: [Pattern] = []

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            patterns.append(pattern)
        }

        var last: Pattern? {
            lock.lock()
            defer { lock.unlock() }
            return patterns.last
        }
    }

    // MARK: - Entrar y salir

    /// **El modificador solo no publica.** Un modificador que además actúa se
    /// dispara sin querer; es el mismo criterio que el 15 y el 16.
    func testTheModifierPressedAloneDoesNotPublish() {
        let (input, published) = makeInput()

        XCTAssertFalse(input.receive(tempModifier()))

        XCTAssertTrue(published.patterns.isEmpty, "hundir el step 13 publicó por sí solo")
    }

    /// Soltarlo sin haber girado nada tampoco publica: el gesto entero se queda
    /// en nada.
    func testReleasingWithoutTurningAnythingDoesNotPublish() {
        let (input, published) = makeInput()

        input.receive(tempModifier())
        XCTAssertFalse(input.receive(tempModifier(value: 0)))

        XCTAssertTrue(published.patterns.isEmpty)
    }

    /// **Soltar tras un giro publica una vez el snapshot restaurado** (FR9).
    func testReleasingAfterATurnPublishesTheRestoredSnapshot() {
        let (input, published) = makeInput()
        let before = input.track

        input.receive(tempModifier())
        XCTAssertTrue(input.receive(knob(.pulses, by: 2)))
        let publishedByTheTurn = published.patterns.count

        XCTAssertTrue(input.receive(tempModifier(value: 0)))

        XCTAssertEqual(
            published.patterns.count, publishedByTheTurn + 1,
            "soltar no publicó exactamente una vez")
        XCTAssertEqual(input.track, before, "soltar no devolvió el Cycle a como estaba")
    }

    // MARK: - Girar con Temp puesto

    /// Con Temp activo, girar publica un Pattern con el overlay: **lo que suena
    /// cambia**.
    func testTurningWithTempActiveOverlaysTheTrack() {
        let (input, published) = makeInput(pulses: 5)

        input.receive(tempModifier())
        XCTAssertTrue(input.receive(knob(.pulses, by: 2)))

        XCTAssertEqual(published.last?.editingCycle(at: 0)?.shape.pulses.count, 7)
    }

    /// **Y no queda rastro en el Pattern** (FR5): tras soltar, el Cycle es el de
    /// partida.
    func testAfterReleasingNothingWasWrittenToThePattern() {
        let (input, _) = makeInput(pulses: 5)

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 2))
        input.receive(knob(.velocity, by: 10))
        input.receive(tempModifier(value: 0))

        XCTAssertEqual(input.track.shape.pulses.count, 5)
        XCTAssertEqual(input.track.groove.velocity.value, 100)
    }

    /// **Girar sin Temp sigue escribiendo permanente.** El gesto añade un modo
    /// mientras se mantiene y no cambia nada de lo que ya había.
    func testTurningWithoutTempStillWritesPermanently() {
        let (input, _) = makeInput(pulses: 5)

        XCTAssertTrue(input.receive(knob(.pulses, by: 2)))

        XCTAssertEqual(input.track.shape.pulses.count, 7, "el giro normal dejó de escribir")
    }

    /// El overlay iguala a todos los Cycles activos: con tres activos, el
    /// parámetro girado suena igual en los tres durante el hold.
    func testTheOverlayEqualisesEveryActiveCycle() {
        let (input, published) = makeInput(pulses: 5)
        input.setActiveCycleCount(3)

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 2))

        let track = published.last?.track(at: 0)
        for index in 0..<3 {
            XCTAssertEqual(
                track?.cycle(at: index)?.shape.pulses.count, 7,
                "el Cycle \(index + 1) no quedó igualado")
        }
    }

    // MARK: - Lo que no publica (FR9)

    /// Un giro nulo no publica, con Temp activo igual que sin él.
    func testANullTurnDoesNotPublishWithTempActive() {
        let (input, published) = makeInput()

        input.receive(tempModifier())
        XCTAssertFalse(input.receive(knob(.pulses, by: 0)))

        XCTAssertTrue(published.patterns.isEmpty)
    }

    /// Un giro contra un extremo tampoco.
    func testATurnAgainstAnExtremeDoesNotPublishWithTempActive() {
        let (input, published) = makeInput(pulses: 16)

        input.receive(tempModifier())
        XCTAssertFalse(input.receive(knob(.pulses, by: 1)))

        XCTAssertTrue(published.patterns.isEmpty)
    }

    /// Y si nunca cambió nada, soltar tampoco publica: no hay snapshot que
    /// restaurar.
    func testReleasingAfterOnlyNullTurnsDoesNotPublish() {
        let (input, published) = makeInput(pulses: 16)

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 1))
        XCTAssertFalse(input.receive(tempModifier(value: 0)))

        XCTAssertTrue(published.patterns.isEmpty)
    }

    // MARK: - Corriendo y parado (FR7)

    /// **El gesto no consulta el transporte.** `ControlInput` no lo conoce
    /// siquiera, y ese es el punto: un gesto que cambiara de significado según
    /// el transporte sería un gesto que hay que recordar. Lo que este test fija
    /// es que la secuencia completa da el mismo resultado sin nada que la
    /// arranque, que es el caso «parado».
    func testTheGestureBehavesTheSameWithTheTransportStopped() {
        let (input, _) = makeInput(pulses: 5)
        let before = input.track

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 3))
        XCTAssertEqual(
            input.track.shape.pulses.count, 8, "el overlay no entró con el transporte parado")

        input.receive(tempModifier(value: 0))
        XCTAssertEqual(input.track, before)
    }

    // MARK: - Varios giros

    /// Girar dos veces el mismo knob acumula sobre el valor superpuesto, y
    /// soltar devuelve el base de una vez.
    func testSeveralTurnsAccumulateAndRestoreInOneGo() {
        let (input, _) = makeInput(pulses: 5)

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 2))
        input.receive(knob(.pulses, by: 3))
        XCTAssertEqual(input.track.shape.pulses.count, 10)

        input.receive(tempModifier(value: 0))
        XCTAssertEqual(input.track.shape.pulses.count, 5)
    }

    /// Dos parámetros distintos durante el mismo hold vuelven los dos.
    func testTwoParametersDuringTheSameHoldBothCameBack() {
        let (input, _) = makeInput(pulses: 5)
        let before = input.track

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 4))
        input.receive(knob(.velocity, by: -20))
        input.receive(tempModifier(value: 0))

        XCTAssertEqual(input.track, before)
    }

    /// Dos holds seguidos: el segundo parte del Pattern original, no del
    /// overlay del primero.
    func testASecondHoldStartsFromTheOriginalPattern() {
        let (input, _) = makeInput(pulses: 5)
        let before = input.track

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 2))
        input.receive(tempModifier(value: 0))

        input.receive(tempModifier())
        input.receive(knob(.pulses, by: 3))
        XCTAssertEqual(
            input.track.shape.pulses.count, 8, "el segundo hold partió del overlay del primero")

        input.receive(tempModifier(value: 0))
        XCTAssertEqual(input.track, before)
    }

    // MARK: - Helpers

    private func makeInput(pulses: Int = 5) -> (ControlInput, Published) {
        let published = Published()
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!)),
            publish: published.record
        )
        return (input, published)
    }

    /// El step button 13, que es el índice 12 del bloque.
    private func tempModifier(value: Int = 127) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(
                ControlMapping.beatStepPro.stepButtonBlock.number
                    + ControlInput.tempModifierIndex)!,
            value: UInt8(value)
        )
    }

    /// Un giro del knob que mapea ese parámetro, en complemento a dos.
    private func knob(_ parameter: TrackParameter, by delta: Int) -> MIDIMessage {
        let controller = ControlMapping.beatStepPro.controller(for: parameter)!
        let value = delta >= 0 ? UInt8(delta) : UInt8(128 + delta)
        return .controlChange(channel: MIDIChannel(1)!, controller: controller, value: value)
    }
}
