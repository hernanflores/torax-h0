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

    // MARK: - Shape, segunda línea

    /// **El card de Shape pasa a dos líneas el 2026-09-07** (FR15): los cuatro
    /// de siempre arriba y los cuatro del Note Repeater debajo. La separación
    /// dice lo que dice el modelo — una capa sobre el ritmo, no el ritmo.
    func testShapeCarriesTheNoteRepeaterOnASecondLine() {
        let readout = FamilyReadout(track: track, family: .shape)
        XCTAssertEqual(
            readout.secondaryDetail, "Repeats 0 · Time 1/32 · Ramp 0% · Pace 0%")
    }

    /// Y escribe lo que tenga puesto, con el signo de Ramp y Pace.
    func testTheSecondLineFollowsTheValues() {
        let moved =
            track
            .applying(4, to: .repeats)
            .applying(1, to: .repeatTime)
            .applying(-30, to: .ramp)
            .applying(60, to: .pace)
        let readout = FamilyReadout(track: moved, family: .shape)

        XCTAssertEqual(
            readout.secondaryDetail, "Repeats 4 · Time 1/48 · Ramp -30% · Pace +60%")
    }

    /// **Las otras dos familias no tienen segunda línea**, y es `nil` y no una
    /// cadena vacía: la vista pregunta si la hay.
    func testOnlyShapeHasASecondLine() {
        XCTAssertNil(FamilyReadout(track: track, family: .groove).secondaryDetail)
        XCTAssertNil(FamilyReadout(track: track, family: .tonal).secondaryDetail)
    }

    /// Los ocho de Shape aparecen entre la lectura grande y las dos líneas: **no
    /// se pierde ninguno** al partirlos en tres.
    func testEveryShapeParameterIsShownSomewhere() {
        let readout = FamilyReadout(track: track, family: .shape)
        let shown =
            readout.headline + " · " + readout.detail + " · " + (readout.secondaryDetail ?? "")

        for name in ["Steps", "Pulses", "Rotate", "Division", "Repeats", "Time", "Ramp", "Pace"] {
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

    // MARK: - Etiqueta y valor por separado

    // **El handoff de iPadOS parte la lectura grande en dos**: `pulses` en
    // pequeño encima y `5 / 16` grande debajo. Hasta el 2026-09-06 `headline`
    // devolvía las dos cosas pegadas —«Pulses 5»— y partirla en la vista habría
    // sido buscar el espacio dentro de una cadena de dominio: se rompe en
    // silencio en cuanto un valor lleve espacio, como `1/16`.

    func testShapeSplitsIntoLabelAndValue() {
        let readout = FamilyReadout(
            track: .init(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!)), family: .shape)
        XCTAssertEqual(readout.label, "Pulses")
        XCTAssertEqual(readout.value, "5 / 16")
    }

    func testShapeValueShowsPulsesOverSteps() {
        // Pulses solo significa algo contra los Steps en los que reparte: 5 de 16
        // y 5 de 12 son dos densidades distintas. El handoff escribe las dos.
        let readout = FamilyReadout(
            track: .init(shape: Shape(steps: Steps(12)!, pulses: Pulses(5)!)), family: .shape)
        XCTAssertEqual(readout.value, "5 / 12")
    }

    func testShapeValueKeepsTheIntendedPulsesNotTheEffectiveOnes() {
        // La enmienda del 2026-08-27: Pulses guarda la intención, no lo que cabe.
        // La lectura enseña lo que el knob dice, que es lo que el usuario acaba
        // de girar; lo que suena es min(pulses, steps) y lo enseña el anillo.
        let shape = Shape(steps: Steps(4)!, pulses: Pulses(9)!)
        let readout = FamilyReadout(track: .init(shape: shape), family: .shape)
        XCTAssertEqual(readout.value, "9 / 4")
        XCTAssertEqual(shape.effectivePulses, 4)
    }

    func testGrooveSplitsIntoLabelAndValue() {
        let readout = FamilyReadout(
            track: .init(shape: Shape(steps: Steps(16)!, pulses: Pulses(1)!)), family: .groove)
        XCTAssertEqual(readout.label, "Velocity")
        XCTAssertFalse(readout.value.contains("Velocity"))
    }

    func testTonalGetsALabelWithoutChangingWhatItSays() {
        // En Tonal la etiqueta se **añade**: el marco es el valor —TONAL no tiene
        // knob detrás— y el headline siempre fue `C Minor` a secas. Partirlo
        // habría cambiado lo que dice la pantalla en reposo, que es texto
        // establecido y con tests propios.
        let readout = FamilyReadout(
            track: .init(shape: Shape(steps: Steps(16)!, pulses: Pulses(1)!)), family: .tonal)
        XCTAssertEqual(readout.label, "Scale")
        XCTAssertEqual(readout.value, readout.headline)
    }

    func testLabelAndValueRebuildTheHeadlineInGroove() {
        // Groove sigue siendo «nombre valor», así que partir no cambió nada.
        // Shape queda fuera porque su lectura añade el denominador, y Tonal
        // porque su etiqueta es nueva: las dos excepciones están documentadas en
        // el propio tipo.
        let track = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(1)!))
        let readout = FamilyReadout(track: track, family: .groove)
        XCTAssertEqual("\(readout.label) \(readout.value)", readout.headline)
    }
}
