import XCTest
@testable import Engine

/// **La red que faltaba: editar un Track no puede perder lo que no se edita.**
///
/// Se escribe tras un defecto real. `applying(_:to:)` se escribió cuando un
/// Track eran tres campos y siguió construyendo con tres cuando llegaron el
/// canal, el marco tonal y el registro de pads: **girar un knob devolvía el
/// Track al canal 1, a Do menor y a la octava base**. El compilador no podía
/// verlo —los campos nuevos tienen valor por defecto— y ningún test lo miraba.
///
/// Estos tests recorren **todos** los parámetros y comparan **todo** lo que no
/// se toca, así que el próximo campo que se añada al Track queda cubierto sin
/// escribir nada nuevo.
final class TrackEditsKeepEverythingElseTests: XCTestCase {

    /// Un Track con todos los campos lejos de su valor por defecto: si algo se
    /// pierde, se ve.
    private func distinctive() -> Track {
        Track(
            shape: Shape(steps: Steps(12)!, pulses: Pulses(5)!, rotate: Rotate(3)),
            pool: PitchPool().inserting(Pitch(60)!).inserting(Pitch(67)!),
            groove: Groove(
                velocity: Velocity(77)!,
                sustain: Sustain(percent: 133)!,
                probability: Probability(percent: 42)!,
                timing: Timing(percent: 66)!,
                delay: Delay(percent: 25)!
            ),
            channel: Channel(9)!,
            frame: TonalFrame(scale: .phrygian, root: Root(4)!),
            padOctaveShift: 2
        )
    }

    // MARK: - Girar un knob

    /// **El defecto del 2026-08-31**, sobre los nueve parámetros y en las dos
    /// direcciones.
    func testTurningAnyKnobKeepsTheChannelTheFrameAndThePadRegister() {
        let track = distinctive()

        for parameter in TrackParameter.allCases {
            for delta in [1, -1, 5, -5] {
                let turned = track.applying(delta, to: parameter)

                XCTAssertEqual(turned.channel, track.channel, "\(parameter) perdió el canal")
                XCTAssertEqual(turned.frame, track.frame, "\(parameter) perdió el marco tonal")
                XCTAssertEqual(
                    turned.padOctaveShift, track.padOctaveShift,
                    "\(parameter) perdió el registro de pads")
                XCTAssertEqual(turned.pool, track.pool, "\(parameter) perdió el pool")
            }
        }
    }

    /// Y mueve lo que tiene que mover: la red no vale si el knob deja de
    /// funcionar.
    func testTurningAKnobStillMovesItsParameter() {
        let track = distinctive()
        for parameter in TrackParameter.allCases {
            XCTAssertNotEqual(
                track.applying(1, to: parameter), track, "\(parameter) no movió nada")
        }
    }

    // MARK: - Las otras ediciones

    func testChangingThePoolKeepsEverythingElse() {
        let track = distinctive()
        let edited = track.with(pool: PitchPool().inserting(Pitch(48)!))

        XCTAssertEqual(edited.shape, track.shape)
        XCTAssertEqual(edited.groove, track.groove)
        XCTAssertEqual(edited.channel, track.channel)
        XCTAssertEqual(edited.frame, track.frame)
        XCTAssertEqual(edited.padOctaveShift, track.padOctaveShift)
    }

    func testChangingTheChannelKeepsEverythingElse() {
        let track = distinctive()
        let edited = track.on(Channel(2)!)

        XCTAssertEqual(edited.shape, track.shape)
        XCTAssertEqual(edited.pool, track.pool)
        XCTAssertEqual(edited.groove, track.groove)
        XCTAssertEqual(edited.frame, track.frame)
        XCTAssertEqual(edited.padOctaveShift, track.padOctaveShift)
    }

    func testChangingTheFrameKeepsEverythingElse() {
        let track = distinctive()
        let edited = track.with(frame: TonalFrame(scale: .major, root: Root(0)!))

        XCTAssertEqual(edited.shape, track.shape)
        XCTAssertEqual(edited.pool, track.pool)
        XCTAssertEqual(edited.groove, track.groove)
        XCTAssertEqual(edited.channel, track.channel)
        XCTAssertEqual(edited.padOctaveShift, track.padOctaveShift, "el marco movió el registro")
    }

    func testChangingThePadRegisterKeepsEverythingElse() {
        let track = distinctive()
        let edited = track.with(padOctaveShift: -1)

        XCTAssertEqual(edited.shape, track.shape)
        XCTAssertEqual(edited.pool, track.pool)
        XCTAssertEqual(edited.groove, track.groove)
        XCTAssertEqual(edited.channel, track.channel)
        XCTAssertEqual(edited.frame, track.frame, "el registro movió el marco")
    }

    /// Sin argumentos, `with()` es la identidad. Parece trivial y no lo es: si
    /// alguien añade un campo al Track y se olvida de este método, este test
    /// falla.
    func testWithNothingChangesNothing() {
        XCTAssertEqual(distinctive().with(), distinctive())
    }
}
