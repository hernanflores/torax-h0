import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de la convivencia entre Temp y Ctrl All (FR13).
///
/// **Son dos modificadores que hacen cosas incompatibles sobre lo mismo.** Temp
/// iguala un parámetro en los Cycles del Track seleccionado; Ctrl All lo
/// desplaza en los doce. Con los dos hundidos hay que elegir, y la regla es que
/// **manda Temp** — no porque sea mejor, sino porque el corte que ya tenía en
/// `receive(_:)` desde `temp-parameters_20260904` dice que con el 13 hundido el
/// único step button vivo es el 13, y respetarlo es más barato que inventar un
/// desempate.
///
/// **Ninguno hereda el estado del otro.** Al soltar el 13 con el 14 aún hundido,
/// Temp restaura y publica, y Ctrl All arranca ahí, sobre el Pattern ya
/// devuelto. La alternativa —dejar el 14 consumido hasta soltarlo y volver a
/// pulsarlo— dejaría un botón hundido que no hace nada, y un botón hundido que
/// no hace nada no tiene forma de explicarse.
final class TempAndCtrlAllTests: XCTestCase {

    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var patterns: [Pattern] = []

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            patterns.append(pattern)
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return patterns.count
        }
    }

    // MARK: - Con los dos hundidos manda Temp

    /// Con 13 y luego 14, los giros son de Temp: alcanzan al Track seleccionado
    /// y no a los demás.
    func testWithBothHeldTheTurnIsTemp() {
        let (input, _) = makeInput()

        input.receive(temp())
        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 2))

        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 0)?.shape.pulses.count, 6)
        XCTAssertEqual(
            input.pattern.track(at: 1)?.cycle(at: 0)?.shape.pulses.count, 1,
            "el giro alcanzó a otro Track: mandó Ctrl All")
    }

    /// **Y el orden de pulsación no importa**: 14 y luego 13 llega al mismo
    /// sitio, porque el 13 se despacha antes de que el 14 pueda registrarse.
    func testTheOrderOfPressingDoesNotMatter() {
        let (input, _) = makeInput()

        input.receive(ctrlAll())
        input.receive(temp())
        input.receive(knob(.pulses, by: 2))

        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 0)?.shape.pulses.count, 6)
        XCTAssertEqual(
            input.pattern.track(at: 1)?.cycle(at: 0)?.shape.pulses.count, 1,
            "con 14 pulsado primero mandó Ctrl All")
    }

    // MARK: - Soltar el 13 con el 14 hundido

    /// **Temp restaura y publica, y Ctrl All arranca sobre el Pattern devuelto.**
    func testReleasingTempRestoresAndCtrlAllStartsFromThere() {
        let (input, published) = makeInput()
        let before = input.pattern

        input.receive(ctrlAll())
        input.receive(temp())
        input.receive(knob(.pulses, by: 2))
        let afterTempTurn = published.count

        // Soltar el 13 devuelve lo que Temp superpuso, y publica una vez.
        XCTAssertTrue(input.receive(temp(value: 0)))
        XCTAssertEqual(input.pattern, before, "Temp no restauró al soltar")
        XCTAssertEqual(published.count, afterTempTurn + 1)

        // A partir de aquí los giros son Ctrl All, con base en el Pattern devuelto.
        input.receive(knob(.pulses, by: 2))
        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 0)?.shape.pulses.count, 6)
        XCTAssertEqual(
            input.pattern.track(at: 1)?.cycle(at: 0)?.shape.pulses.count, 3,
            "tras soltar el 13, el giro no alcanzó a los demás Tracks")
    }

    /// Y soltar después el 14 devuelve el Pattern entero: la base que tomó Ctrl
    /// All era la restaurada, no la que Temp tenía superpuesta.
    func testReleasingCtrlAllAfterwardsReturnsTheOriginal() {
        let (input, _) = makeInput()
        let before = input.pattern

        input.receive(ctrlAll())
        input.receive(temp())
        input.receive(knob(.pulses, by: 2))
        input.receive(temp(value: 0))
        input.receive(knob(.pulses, by: 3))
        input.receive(ctrlAll(value: 0))

        XCTAssertEqual(input.pattern, before, "el Pattern no volvió a su sitio")
    }

    // MARK: - Soltar el 14 antes que el 13

    /// **Soltar el 14 con el 13 hundido no restaura el Temp por adelantado ni
    /// deja nada pegado.** El 14 nunca llegó a estar al mando, así que su soltada
    /// no tiene nada que devolver.
    func testReleasingCtrlAllFirstDoesNotDisturbTemp() {
        let (input, _) = makeInput()
        let before = input.pattern

        input.receive(ctrlAll())
        input.receive(temp())
        input.receive(knob(.pulses, by: 2))

        // La soltada del 14 se ignora entera: el corte de Temp la bloquea.
        XCTAssertFalse(input.receive(ctrlAll(value: 0)))
        XCTAssertEqual(
            input.pattern.track(at: 0)?.cycle(at: 0)?.shape.pulses.count, 6,
            "soltar el 14 deshizo el Temp en curso")

        // Y el Temp sigue vivo: soltarlo devuelve.
        input.receive(temp(value: 0))
        XCTAssertEqual(input.pattern, before)
    }

    /// Tras ese cruce, el 14 no quedó armado: un giro suelto escribe normal.
    func testAfterTheCrossoverNothingIsLeftArmed() {
        let (input, _) = makeInput()

        input.receive(ctrlAll())
        input.receive(temp())
        input.receive(ctrlAll(value: 0))
        input.receive(temp(value: 0))

        input.receive(knob(.pulses, by: 2))

        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 0)?.shape.pulses.count, 6)
        XCTAssertEqual(
            input.pattern.track(at: 1)?.cycle(at: 0)?.shape.pulses.count, 1,
            "quedó un Ctrl All armado tras el cruce")
    }

    // MARK: - Lo que la pantalla puede preguntar

    /// `isTempActive` y `isCtrlAllActive` no se contradicen: con los dos
    /// hundidos, solo Temp está activo, porque el 14 nunca se registró.
    func testTheTwoReadersDoNotContradictEachOther() {
        let (input, _) = makeInput()

        input.receive(temp())
        input.receive(ctrlAll())

        XCTAssertTrue(input.isTempActive)
        XCTAssertFalse(input.isCtrlAllActive, "la pantalla vería los dos gestos a la vez")
    }

    // MARK: - Helpers

    /// **El Track 1 arranca con este Cycle y los otros once con el de por
    /// defecto**, que trae Pulses 1: `ControlInput(track:)` siembra solo el
    /// primero. Los asertos de abajo cuentan con eso —Track 1 en 4, Track 2 en
    /// 1— en vez de suponer que los doce parten del mismo sitio, que es el error
    /// que hizo fallar estos tests mientras se escribían.
    private func makeInput() -> (ControlInput, Published) {
        let published = Published()
        let input = ControlInput(
            track: Cycle(
                shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!),
                pool: PitchPool().inserting(Pitch(48)!),
                groove: Groove(
                    velocity: Velocity(64)!,
                    sustain: Sustain(percent: 100)!,
                    probability: Probability(percent: 50)!,
                    timing: Timing(percent: 60)!,
                    delay: Delay(percent: 0)!
                )
            ),
            publish: published.record
        )
        return (input, published)
    }

    private func temp(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.tempModifierIndex, value: value)
    }

    private func ctrlAll(value: Int = 127) -> MIDIMessage {
        stepButton(ControlInput.ctrlAllModifierIndex, value: value)
    }

    private func stepButton(_ index: Int, value: Int = 127) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(ControlMapping.beatStepPro.stepButtonBlock.number + index)!,
            value: UInt8(value)
        )
    }

    private func knob(_ parameter: TrackParameter, by delta: Int) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: ControlMapping.beatStepPro.controller(for: parameter)!,
            value: delta >= 0 ? UInt8(delta) : UInt8(128 + delta)
        )
    }
}
