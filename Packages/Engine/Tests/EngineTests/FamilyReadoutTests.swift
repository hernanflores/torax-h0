import XCTest

@testable import Engine

/// Tests de qué dice el panel de lectura en reposo.
///
/// **Es texto, y el texto es dominio.** `workflow.md` manda que lo calculable no
/// viva en `App`: qué valor encabeza cada familia y cómo se escribe son
/// decisiones que se rompen en silencio —una etiqueta mal puesta sigue
/// dibujándose— así que se fijan aquí.
///
/// La forma es la del handoff: una lectura grande y una línea pequeña debajo.
/// **La grande tiene el mismo formato que un valor transitorio** —término de la
/// Pre Spec y valor, sin adornos— para que reposo y giro no se lean como dos
/// cosas distintas.
final class FamilyReadoutTests: XCTestCase {

    private let track = Cycle(
        shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
        pool: PitchPool().inserting(Pitch(48)!).inserting(Pitch(55)!),
        frame: TonalFrame(scale: .minor, root: .c)
    )

    // MARK: - Shape

    func testShapeLeadsWithPulsesAndDetailsTheRest() {
        let readout = FamilyReadout(track: track, family: .shape)

        XCTAssertEqual(readout.headline, "Pulses 5")
        XCTAssertEqual(readout.detail, "Steps 16 · Rotate 0 · Division 1/16")
    }

    // MARK: - Groove

    func testGrooveLeadsWithVelocityAndDetailsTheOtherFour() {
        let readout = FamilyReadout(track: track, family: .groove)

        XCTAssertEqual(readout.headline, "Velocity 100")
        XCTAssertEqual(
            readout.detail, "Sustain 100% · Probability 100% · Timing 50% · Delay 0%")
    }

    /// Los cinco de Groove aparecen entre la lectura grande y el detalle: **no se
    /// pierde ninguno** al partirlos en dos.
    func testEveryGrooveParameterIsShownSomewhere() {
        let readout = FamilyReadout(track: track, family: .groove)
        let shown = readout.headline + " · " + readout.detail

        for name in ["Velocity", "Sustain", "Probability", "Timing", "Delay"] {
            XCTAssertTrue(shown.contains(name), "falta \(name)")
        }
    }

    // MARK: - Tonal

    /// **TONAL no tiene parámetros de knob detrás** (FR4), así que su lectura en
    /// reposo es el marco tonal y el pool: Scale, Root y cuántas alturas hay.
    func testTonalLeadsWithTheFrameAndCountsThePool() {
        let readout = FamilyReadout(track: track, family: .tonal)

        XCTAssertEqual(readout.headline, "C Minor")
        XCTAssertEqual(readout.detail, "Pool · 2 pitches")
    }

    /// **Con el pool vacío se dice, y no se inventa material que no hay.** Un
    /// Track sin pool dispara sus Pulses y no emite: la pantalla tiene que
    /// comunicar ese estado, que es el de quince Tracks al arrancar.
    func testAnEmptyPoolIsStatedAndNotInvented() {
        let empty = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!))

        XCTAssertEqual(FamilyReadout(track: empty, family: .tonal).detail, "Pool · empty")
    }

    /// Una sola altura se dice en singular. Es la diferencia entre una app que
    /// informa y una que rellena una plantilla.
    func testASinglePitchReadsInTheSingular() {
        let one = Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: PitchPool().inserting(Pitch(48)!))

        XCTAssertEqual(FamilyReadout(track: one, family: .tonal).detail, "Pool · 1 pitch")
    }

    func testTheFrameFollowsTheTrackAndNotTheApp() {
        let dorian = track.with(frame: TonalFrame(scale: .dorian, root: Root(7)!))

        XCTAssertEqual(FamilyReadout(track: dorian, family: .tonal).headline, "G Dorian")
    }

    // MARK: - La forma

    /// Las tres familias tienen lectura: ninguna cae en un caso vacío, que es lo
    /// que pasaría si alguien añadiera una familia y olvidara su texto.
    func testEveryFamilyHasSomethingToSay() {
        for family in ParameterFamily.allCases {
            let readout = FamilyReadout(track: track, family: family)
            XCTAssertFalse(readout.headline.isEmpty, "\(family)")
            XCTAssertFalse(readout.detail.isEmpty, "\(family)")
        }
    }

    /// **La lectura grande se escribe como un valor transitorio.** Girar el knob
    /// de Pulses hasta 5 y estar en reposo con Pulses 5 producen exactamente el
    /// mismo texto grande, así que el panel no cambia de idioma según de dónde
    /// venga lo que muestra.
    func testTheHeadlineMatchesWhatATransientWouldSay() {
        let moved = track.applying(1, to: .pulses)
        let change = ParameterChange(from: track, to: moved)

        XCTAssertEqual(change?.description, "Pulses 6")
        XCTAssertEqual(FamilyReadout(track: moved, family: .shape).headline, "Pulses 6")
    }
}
