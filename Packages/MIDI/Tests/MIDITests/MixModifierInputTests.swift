import Engine
import XCTest
@testable import MIDI

/// Tests del gesto de mezcla en el controlador (FR7, FR8).
///
/// **Mantener el step button 16 y pulsar el N mutea el Track N**; con el 15, lo
/// solea. Los dos quedaron libres al bajar a doce Tracks, así que el gesto no le
/// quita nada a la selección.
///
/// **Sin temporizador, y eso es el punto.** El BeatStep manda 127 al pulsar y 0
/// al soltar, así que «mantenido» es estado de mensajes: nada se difiere, nada
/// se adivina, y el gesto entero se prueba con mensajes. Una pulsación larga o
/// una doble habrían exigido un reloj dentro del camino de entrada y diferir la
/// selección hasta saber qué fue.
final class MixModifierInputTests: XCTestCase {

    /// Lo que el gesto produce, en orden.
    private final class Gestures: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var recorded: [MixGesture] = []

        func record(_ gesture: MixGesture) {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(gesture)
        }
    }

    // MARK: - El gesto

    /// Mantener el 16 y pulsar el 3 mutea el Track 3.
    func testHoldingTheMuteModifierTurnsAStepButtonIntoAMute() {
        let (input, gestures) = makeInput()

        input.receive(stepButton(15))
        XCTAssertTrue(input.receive(stepButton(2)))

        XCTAssertEqual(gestures.recorded, [.mute(2)])
    }

    /// Mantener el 15 hace lo mismo con el solo.
    func testHoldingTheSoloModifierTurnsAStepButtonIntoASolo() {
        let (input, gestures) = makeInput()

        input.receive(stepButton(14))
        XCTAssertTrue(input.receive(stepButton(2)))

        XCTAssertEqual(gestures.recorded, [.solo(2)])
    }

    /// **Y no cambia el Track seleccionado.** Es lo que hace del gesto un
    /// modificador y no un modo: se mutea el Track 3 sin dejar de editar el que
    /// se estuviera editando.
    func testTheGestureDoesNotMoveTheSelection() {
        let (input, _) = makeInput()
        input.receive(stepButton(1))
        XCTAssertEqual(input.selectedTrackIndex, 1)

        input.receive(stepButton(15))
        input.receive(stepButton(4))

        XCTAssertEqual(input.selectedTrackIndex, 1)
    }

    /// Soltar el modificador devuelve los step buttons a lo que eran.
    func testReleasingTheModifierGivesTheStepButtonsBack() {
        let (input, gestures) = makeInput()

        input.receive(stepButton(15))
        input.receive(stepButton(3))
        input.receive(stepButton(15, value: 0))
        XCTAssertTrue(input.receive(stepButton(3)))

        XCTAssertEqual(gestures.recorded, [.mute(3)])
        XCTAssertEqual(input.selectedTrackIndex, 3)
    }

    /// Con el modificador mantenido se pueden mutear varios seguidos, que es
    /// como se usa de verdad.
    func testSeveralTracksCanBeMutedWithoutReleasingTheModifier() {
        let (input, gestures) = makeInput()

        input.receive(stepButton(15))
        input.receive(stepButton(0))
        input.receive(stepButton(4))
        input.receive(stepButton(9))

        XCTAssertEqual(gestures.recorded, [.mute(0), .mute(4), .mute(9)])
    }

    /// La soltada del step button no repite el gesto: alternar en la pulsación
    /// **y** en la soltada sería no alternar.
    func testTheReleaseOfTheStepButtonDoesNotRepeatTheGesture() {
        let (input, gestures) = makeInput()

        input.receive(stepButton(15))
        input.receive(stepButton(2))
        input.receive(stepButton(2, value: 0))

        XCTAssertEqual(gestures.recorded, [.mute(2)])
    }

    // MARK: - Lo que no hace

    /// **Los modificadores pulsados solos no hacen nada.** Un modificador que
    /// además actúa es un modificador que se dispara sin querer.
    func testTheModifiersPressedAloneDoNothing() {
        let (input, gestures) = makeInput()
        let selected = input.selectedTrackIndex

        XCTAssertFalse(input.receive(stepButton(15)))
        XCTAssertFalse(input.receive(stepButton(15, value: 0)))
        XCTAssertFalse(input.receive(stepButton(14)))
        XCTAssertFalse(input.receive(stepButton(14, value: 0)))

        XCTAssertTrue(gestures.recorded.isEmpty)
        XCTAssertEqual(input.selectedTrackIndex, selected)
    }

    /// **Los dos mantenidos a la vez: manda el de mute.** Da igual cuál sea la
    /// respuesta correcta mientras sea *una*: un gesto ambiguo que a veces
    /// mutea y a veces solea es peor que cualquiera de las dos.
    func testWithBothModifiersHeldMuteWins() {
        let (input, gestures) = makeInput()

        input.receive(stepButton(14))
        input.receive(stepButton(15))
        input.receive(stepButton(6))

        XCTAssertEqual(gestures.recorded, [.mute(6)])
    }

    /// Un step button sin Track detrás no produce gesto, con el mismo criterio
    /// que ya rige para la selección.
    func testAStepButtonWithNoTrackBehindItProducesNoGesture() {
        let (input, gestures) = makeInput(trackCount: 4)

        input.receive(stepButton(15))
        XCTAssertFalse(input.receive(stepButton(9)))

        XCTAssertTrue(gestures.recorded.isEmpty)
    }

    /// Sin nadie escuchando los gestos, el modificador sigue sin seleccionar: no
    /// se cae de vuelta a la selección porque nadie recoja el gesto.
    func testWithNoListenerTheModifierStillBlocksSelection() {
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            publish: { _ in },
            trackCount: Pattern.trackCount
        )

        input.receive(stepButton(15))
        XCTAssertFalse(input.receive(stepButton(3)))
        XCTAssertEqual(input.selectedTrackIndex, 0)
    }

    // MARK: - Soltarse solos (FR8)

    /// **Reconectar suelta los modificadores.** Un cable desenchufado con el
    /// botón hundido dejaría el modificador pegado para siempre, y desde la app
    /// no hay forma de soltarlo: la soltada que lo haría nunca va a llegar.
    func testReconnectingReleasesTheHeldModifiers() {
        let (input, gestures) = makeInput()

        input.receive(stepButton(15))
        input.releaseModifiers()

        XCTAssertTrue(input.receive(stepButton(3)))
        XCTAssertTrue(gestures.recorded.isEmpty)
        XCTAssertEqual(input.selectedTrackIndex, 3)
    }

    // MARK: - Helpers

    private func makeInput(trackCount: Int = Pattern.trackCount) -> (ControlInput, Gestures) {
        let gestures = Gestures()
        let input = ControlInput(
            track: Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!)),
            publish: { _ in },
            trackCount: trackCount,
            mix: gestures.record
        )
        return (input, gestures)
    }

    private func stepButton(_ index: Int, value: Int = 127) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: MIDIController(ControlMapping.beatStepPro.stepButtonBlock.number + index)!,
            value: UInt8(value)
        )
    }
}
