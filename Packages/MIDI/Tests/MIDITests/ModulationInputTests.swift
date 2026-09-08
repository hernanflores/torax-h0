import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre.
private typealias Pattern = Engine.Pattern

/// Tests de la vía táctil que escribe la modulación (FR9, FR16, FR17).
///
/// **Vive en `ControlInput` y no en la vista** por la razón de siempre:
/// `workflow.md` dice que si algo en `App` merece un test está en el sitio
/// equivocado. Lo que queda en la pantalla es el dibujo y el gesto; la regla de
/// **sobre qué Cycle se escribe** se prueba aquí.
///
/// **Escribe sobre el Cycle en edición y no sobre el que suena** (FR16), como el
/// resto de la edición táctil: mientras suena el A se construye el B.
///
/// **Ningún CC llega hasta aquí** (FR9). `waveform` y `accent` no son
/// `TrackParameter`, no están en `ControlMapping` y no entran en el preset del
/// BeatStep Pro; hay un barrido de los 128 controladores que lo vigila.
final class ModulationInputTests: XCTestCase {

    private func cycle(pitch: Int = 48) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    /// Recoge lo publicado. `ControlInput` publica desde una clausura
    /// `@Sendable`, así que el acumulador tiene que ser una referencia — mismo
    /// idioma que el `Box` de `EditingCycleInputTests`.
    private final class Published: @unchecked Sendable {
        var patterns: [Pattern] = []
        var count: Int { patterns.count }
    }

    private func input(
        activeCycles: Int = 4,
        editing: Int = 0,
        publish: Published? = nil
    ) -> ControlInput {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(
                Track(cycle()).withActiveCount(activeCycles).withEditing(editing), at: index)
        }
        return ControlInput(
            pattern: pattern,
            publish: { snapshot in publish?.patterns.append(snapshot) }
        )
    }

    private let accented = Modulation(waveform: .pulse, accent: Accent(percent: 70)!)

    // MARK: - Escribe donde debe

    func testItWritesTheModulationOfTheSelectedTrack() {
        let input = input()

        XCTAssertTrue(input.setModulation(accented))

        XCTAssertEqual(input.pattern.editingCycle(at: 0)?.modulation, accented)
    }

    /// **Sobre el Cycle en edición y no sobre el que suena** (FR16).
    func testItWritesTheEditingCycleAndNotTheSoundingOne() {
        // El cursor de edición está en el segundo Cycle; el de reproducción se
        // queda en el primero, que es como se construye el B mientras suena el A.
        let input = input(editing: 1)
        input.selectTrack(0)

        XCTAssertTrue(input.setModulation(accented))

        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 1)?.modulation, accented)
        XCTAssertEqual(input.pattern.track(at: 0)?.cycle(at: 0)?.modulation, .default)
    }

    /// Y no toca a los otros once Tracks.
    func testItLeavesTheOtherElevenTracksAlone() {
        let input = input()

        input.selectTrack(4)
        XCTAssertTrue(input.setModulation(accented))

        XCTAssertEqual(input.pattern.editingCycle(at: 4)?.modulation, accented)
        for index in 0..<Pattern.trackCount where index != 4 {
            XCTAssertEqual(
                input.pattern.editingCycle(at: index)?.modulation, .default, "Track \(index)")
        }
    }

    /// **No mueve la selección ni el cursor de edición.** Ajustar el acento no
    /// debería cambiar a dónde apuntan los knobs (FR17).
    func testItMovesNeitherCursor() {
        let input = input(editing: 2)
        input.selectTrack(3)

        XCTAssertTrue(input.setModulation(accented))

        XCTAssertEqual(input.selectedTrackIndex, 3)
        XCTAssertEqual(input.pattern.track(at: 3)?.editing, 2)
        XCTAssertEqual(input.pattern.track(at: 3)?.cursor, 0)
    }

    /// Y no toca nada más del Cycle: es `Cycle.with(...)`, que enumera los campos
    /// en un solo sitio.
    func testItChangesNothingElseOfTheCycle() {
        let input = input()
        let before = input.pattern.editingCycle(at: 0)!

        XCTAssertTrue(input.setModulation(accented))

        let after = input.pattern.editingCycle(at: 0)!
        XCTAssertEqual(after.shape, before.shape)
        XCTAssertEqual(after.pool, before.pool)
        XCTAssertEqual(after.groove, before.groove)
        XCTAssertEqual(after.channel, before.channel)
        XCTAssertEqual(after.frame, before.frame)
        XCTAssertEqual(after.noteRepeater, before.noteRepeater)
        XCTAssertEqual(after.padOctaveShift, before.padOctaveShift)
    }

    // MARK: - Publica, y solo cuando hace falta

    /// **Publica**, porque el scheduler lee la modulación del snapshot en cada
    /// Step: sin publicar, el acento no se oiría hasta el giro siguiente de
    /// cualquier knob.
    func testItPublishesSoTheAccentIsHeardAtOnce() {
        let published = Published()
        let input = input(publish: published)

        XCTAssertTrue(input.setModulation(accented))

        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(published.patterns.last?.editingCycle(at: 0)?.modulation, accented)
    }

    /// Y **no publica un snapshot idéntico** cuando se vuelve a elegir la onda
    /// que ya estaba: es el criterio que `setFrame` y `setChannel` ya siguen.
    func testItDoesNotPublishWhenNothingChanges() {
        let published = Published()
        let input = input(publish: published)

        XCTAssertTrue(input.setModulation(accented))
        XCTAssertFalse(input.setModulation(accented))

        XCTAssertEqual(published.count, 1)
    }

    /// El neutro sobre un Cycle recién creado tampoco publica.
    func testTheNeutralOnAFreshCycleDoesNotPublish() {
        let published = Published()
        let input = input(publish: published)

        XCTAssertFalse(input.setModulation(.default))

        XCTAssertEqual(published.count, 0)
    }

    // MARK: - Ningún knob la alcanza

    /// **Barrido de los 128 controladores** (FR9): ninguno mueve `waveform` ni
    /// `accent`. Es el mismo barrido que vigila que ningún CC ajuste cuántos
    /// Cycles están activos.
    func testNoControllerEverTouchesTheModulation() {
        let input = input()
        input.setModulation(accented)

        for number in 0...127 {
            guard let controller = MIDIController(number) else { continue }
            for value in [UInt8(0x01), UInt8(0x7F), UInt8(0x40)] {
                input.receive(
                    .controlChange(channel: MIDIChannel(1)!, controller: controller, value: value))
            }
        }

        for index in 0..<Pattern.trackCount {
            let modulation = input.pattern.editingCycle(at: index)?.modulation
            let expected = index == 0 ? accented : Modulation.default
            XCTAssertEqual(modulation, expected, "Track \(index) — un CC movió la modulación")
        }
    }

    /// Y no hay `TrackParameter` que la nombre: la familia se añadiría el día que
    /// `accent` tenga knob, no antes.
    func testTheModulationIsNotATrackParameter() {
        let names = TrackParameter.allCases.map(\.description)
        XCTAssertFalse(names.contains("Accent"))
        XCTAssertFalse(names.contains("Waveform"))
    }
}
