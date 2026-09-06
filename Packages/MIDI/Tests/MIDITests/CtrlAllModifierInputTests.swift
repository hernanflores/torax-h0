import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests del gesto de Ctrl All en el controlador (FR1, FR12, FR14).
///
/// **Mantener el step button 14 y girar un knob desplaza ese parámetro en los
/// doce Tracks sin escribirlo en el Pattern**; al soltar, todo vuelve. Es el
/// cuarto modificador y no inventa mecánica: el 13, el 15 y el 16 ya son Temp,
/// solo y mute con el mismo 127 al pulsar y 0 al soltar.
///
/// **Lo que sí inventa es a quién alcanza.** Temp superpone sobre el Track
/// seleccionado igualando sus Cycles; Ctrl All desplaza los doce conservando sus
/// diferencias. La regla vive en `CtrlAllOffset`, en `Engine`; aquí solo se
/// prueba que el gesto la acciona y que publica cuando debe.
final class CtrlAllModifierInputTests: XCTestCase {

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

        /// Olvida lo publicado al sembrar: lo que se mide es el gesto.
        func clear() {
            lock.lock()
            defer { lock.unlock() }
            patterns.removeAll()
        }
    }

    // MARK: - Entrar y salir

    /// **El modificador solo no publica**, con el mismo criterio que los otros
    /// tres: un modificador que además actúa se dispara sin querer.
    func testTheModifierPressedAloneDoesNotPublish() {
        let (input, published) = makeInput()

        XCTAssertFalse(input.receive(ctrlAll()))

        XCTAssertTrue(published.patterns.isEmpty, "hundir el step 14 publicó por sí solo")
    }

    /// Soltarlo sin haber girado nada tampoco publica.
    func testReleasingWithoutTurningAnythingDoesNotPublish() {
        let (input, published) = makeInput()

        input.receive(ctrlAll())
        XCTAssertFalse(input.receive(ctrlAll(value: 0)))

        XCTAssertTrue(published.patterns.isEmpty)
    }

    // MARK: - El giro alcanza a los doce

    /// **Un giro con el 14 hundido mueve los doce Tracks**, no solo el
    /// seleccionado. Es la diferencia entera con un giro normal.
    func testATurnMovesAllTwelveTracks() {
        let (input, _) = makeInput(pulsesPerTrack: Array(1...12))

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 2))

        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(
                input.pattern.track(at: index)?.cycle(at: 0)?.shape.pulses.count, index + 3,
                "Track \(index + 1)")
        }
    }

    /// **Y conserva las diferencias**: dos Tracks a distancia 5 siguen a
    /// distancia 5.
    func testTheDistanceBetweenTracksSurvivesTheGesture() {
        let (input, _) = makeInput(pulsesPerTrack: [4, 9] + Array(repeating: 5, count: 10))

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 3))

        let first = input.pattern.track(at: 0)!.cycle(at: 0)!.shape.pulses.count
        let second = input.pattern.track(at: 1)!.cycle(at: 0)!.shape.pulses.count
        XCTAssertEqual(first, 7)
        XCTAssertEqual(second, 12)
    }

    /// Soltar devuelve el Pattern y publica una vez.
    func testReleasingRestoresAndPublishesOnce() {
        let (input, published) = makeInput(pulsesPerTrack: Array(1...12))
        let before = input.pattern

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 2))
        let turns = published.patterns.count

        XCTAssertTrue(input.receive(ctrlAll(value: 0)))

        XCTAssertEqual(input.pattern, before, "soltar no devolvió el Pattern")
        XCTAssertEqual(published.patterns.count, turns + 1, "soltar publicó más de una vez")
    }

    /// **Sin el modificador, un giro sigue escribiendo en el Track
    /// seleccionado** y no toca a los demás. El gesto no cambia lo que hace el
    /// controlador el resto del tiempo.
    func testWithoutTheModifierATurnStillWritesOneTrack() {
        let (input, _) = makeInput(pulsesPerTrack: Array(1...12))

        input.receive(knob(.pulses, by: 2))

        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 0)?.shape.pulses.count, 3)
        XCTAssertEqual(
            input.pattern.track(at: 1)?.cycle(at: 0)?.shape.pulses.count, 2,
            "un giro normal alcanzó a otro Track")
    }

    // MARK: - Publicar (FR12)

    /// Un giro nulo no publica.
    func testAZeroTurnDoesNotPublish() {
        let (input, published) = makeInput()

        input.receive(ctrlAll())
        XCTAssertFalse(input.receive(knob(.pulses, by: 0)))

        XCTAssertTrue(published.patterns.isEmpty)
    }

    /// **El caso que separa esta regla de la de Temp** (FR12): el Track
    /// seleccionado está topado, otros se mueven, y **publica**.
    ///
    /// La regla de Temp —«si el Cycle en edición no se mueve, no se mueve
    /// nadie»— existía porque la igualación aplanaba a los demás. Aquí no hay
    /// nada que aplanar, y callar porque el Track que se mira topó silenciaría un
    /// gesto que está sonando.
    func testItPublishesWhenOnlyOtherTracksMove() {
        let (input, published) = makeInput(pulsesPerTrack: [16] + Array(repeating: 5, count: 11))

        input.receive(ctrlAll())
        XCTAssertTrue(
            input.receive(knob(.pulses, by: 1)),
            "el Track seleccionado topó y el gesto se calló")

        XCTAssertEqual(published.patterns.count, 1)
        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 0)?.shape.pulses.count, 16)
        XCTAssertEqual(input.pattern.track(at: 1)?.cycle(at: 0)?.shape.pulses.count, 6)
    }

    /// Y si **ningún** Track puede moverse, no publica: no ha cambiado nada.
    func testItDoesNotPublishWhenNobodyCanMove() {
        let (input, published) = makeInput(pulsesPerTrack: Array(repeating: 16, count: 12))

        input.receive(ctrlAll())
        XCTAssertFalse(input.receive(knob(.pulses, by: 1)))

        XCTAssertTrue(published.patterns.isEmpty)
    }

    // MARK: - El transporte no cambia nada (FR14)

    /// **Ctrl All se comporta igual con el transporte parado.** Un gesto que
    /// cambia de significado según el transporte es un gesto que hay que
    /// recordar; este no consulta el transporte en ningún sitio.
    func testTheGestureIsTheSameWithTheTransportStopped() {
        let (running, _) = makeInput(pulsesPerTrack: Array(1...12))
        let (stopped, _) = makeInput(pulsesPerTrack: Array(1...12))

        for input in [running, stopped] {
            input.receive(ctrlAll())
            input.receive(knob(.pulses, by: 3))
        }

        XCTAssertEqual(running.pattern, stopped.pattern)
    }

    // MARK: - Varios parámetros y varios holds

    /// Cada parámetro lleva su desplazamiento, y soltar devuelve los dos.
    func testTwoParametersInTheSameHoldBothComeBack() {
        let (input, _) = makeInput(pulsesPerTrack: Array(1...12))
        let before = input.pattern

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 2))
        input.receive(knob(.velocity, by: -5))
        input.receive(ctrlAll(value: 0))

        XCTAssertEqual(input.pattern, before)
    }

    /// **Un hold no hereda del anterior:** el segundo parte del Pattern
    /// restaurado, no del desplazamiento del primero.
    func testASecondHoldStartsFromTheRestoredPattern() {
        let (input, _) = makeInput(pulsesPerTrack: Array(1...12))
        let before = input.pattern

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 3))
        input.receive(ctrlAll(value: 0))

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 3))
        XCTAssertEqual(
            input.pattern.track(at: 0)?.cycle(at: 0)?.shape.pulses.count, 4,
            "el segundo hold partió del desplazamiento del primero")

        input.receive(ctrlAll(value: 0))
        XCTAssertEqual(input.pattern, before)
    }

    // MARK: - Helpers

    private func makeInput(pulsesPerTrack: [Int]? = nil) -> (ControlInput, Published) {
        let published = Published()
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)),
            publish: published.record
        )
        // **Se siembra por la vía real**: seleccionar el Track y girar el knob.
        // No hay atajo de test que escriba un Pulses distinto en cada Track, y
        // tampoco debería haberlo — si el sembrado usara una puerta trasera, el
        // Pattern de partida podría ser uno que el controlador no puede producir.
        //
        // **El delta se calcula del valor real de cada Track, no de un supuesto.**
        // `ControlInput(track:)` siembra con ese Cycle **solo el Track 1**; los
        // otros once arrancan con el Pulses por defecto. Dar por hecho que los
        // doce parten del mismo sitio dejaba el Pattern de prueba en algo que no
        // era lo que el test decía, y los asertos fallaban por el sembrado y no
        // por el gesto.
        if let pulsesPerTrack {
            for (index, pulses) in pulsesPerTrack.enumerated() {
                input.selectTrack(index)
                let current = input.pattern.track(at: index)!.cycle(at: 0)!.shape.pulses.count
                input.receive(knob(.pulses, by: pulses - current))
            }
            input.selectTrack(0)
        }
        published.clear()
        return (input, published)
    }

    /// El step button 14, que es el índice 13 del bloque.
    private func ctrlAll(value: Int = 127) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(
                ControlMapping.beatStepPro.stepButtonBlock.number
                    + ControlInput.ctrlAllModifierIndex)!,
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
