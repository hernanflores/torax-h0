import Engine
import Foundation
import XCTest

@testable import MIDI

/// `Pattern` colisiona con el de ApplicationServices, como en el resto de la
/// suite.
private typealias Pattern = Engine.Pattern

/// Tests de la vía de ida: el modelo le dice a `ControlInput` que el material
/// cambió.
///
/// **El fallo que este track existe para arreglar** (`spec.md`): `ControlInput`
/// guarda su propia copia del Pattern y hasta ahora solo la escribía en su
/// `init`, así que después de cambiar de Bank el primer giro de knob
/// republicaba el Pattern anterior entero encima del Bank nuevo.
final class PatternAdoptionTests: XCTestCase {

    /// Lo publicado, con el mismo candado que el resto de la suite: el cierre de
    /// publicación es `@Sendable`.
    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private var patterns: [Pattern] = []

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return patterns.count
        }

        var last: Pattern? {
            lock.lock()
            defer { lock.unlock() }
            return patterns.last
        }

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            patterns.append(pattern)
        }
    }

    // MARK: - Se sustituye el material entero (FR1, FR2)

    /// Adoptar sustituye los doce Tracks, no solo el seleccionado.
    func testAdoptingReplacesEveryTrack() {
        let input = makeInput()
        let adopted = makePattern(steps: 12, pulses: 5, channel: 7)

        input.adopt(adopted)

        XCTAssertEqual(input.pattern, adopted)
        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(
                input.pattern.cycle(at: index), adopted.cycle(at: index), "Track \(index)")
        }
    }

    /// Y con ellos el pool, el Groove, el canal y el registro de pads: todo lo
    /// que viaja en el `Pattern` es material.
    func testAdoptingReplacesPoolGrooveChannelAndPadRegister() {
        let input = makeInput()
        input.receive(pad(0))
        input.receive(pad(15))  // sube una octava el registro de pads

        let cycle = Cycle(
            shape: Shape(steps: Steps(9)!, pulses: Pulses(4)!),
            pool: PitchPool().toggling(Pitch(64)!),
            groove: Groove.default,
            channel: Channel(5)!,
            frame: TonalFrame(scale: .major, root: Root(3)!),
            padOctaveShift: -1
        )
        input.adopt(Pattern().replacing(cycle, at: 0))

        XCTAssertEqual(input.track.pool, cycle.pool, "el pool no se adoptó")
        XCTAssertEqual(input.track.channel, cycle.channel, "el canal no se adoptó")
        XCTAssertEqual(input.track.shape, cycle.shape, "el Shape no se adoptó")
        XCTAssertEqual(input.track.padOctaveShift, -1, "el registro de pads no se adoptó")
        XCTAssertEqual(input.surface.octaveShift, -1)
    }

    /// **El Track seleccionado es del dedo, no del material** (FR2): cambiar de
    /// Bank para seguir tocando el mismo Track es el gesto normal en directo.
    func testAdoptingKeepsTheSelectedTrack() {
        let input = makeInput()
        XCTAssertTrue(input.selectTrack(4))

        input.adopt(makePattern(steps: 12, pulses: 5, channel: 7))

        XCTAssertEqual(input.selectedTrackIndex, 4)
    }

    /// Y con él, a quién escuchan los knobs: girar después de adoptar edita el
    /// Track que estaba seleccionado, no el primero.
    func testTheKnobsStillListenToTheSelectedTrackAfterAdopting() {
        let published = Published()
        let input = makeInput(publish: published.record)
        input.selectTrack(4)
        input.adopt(makePattern(steps: 12, pulses: 5, channel: 7))

        XCTAssertTrue(
            input.receive(knob(ControlMapping.beatStepPro.controller(for: .pulses)!, delta: 1)))

        XCTAssertEqual(published.last?.cycle(at: 4)?.shape.pulses.count, 6)
        XCTAssertEqual(
            published.last?.cycle(at: 0)?.shape.pulses.count, 5, "editó el Track equivocado")
    }

    // MARK: - El marco tonal no se re-siembra (FR3)

    /// El `init` reparte un `TonalFrame` a los doce porque nace sin material; un
    /// Pattern que viene de disco trae el suyo por Cycle y pisarlo sería
    /// destruirlo.
    func testAdoptingKeepsTheFrameOfEachAdoptedCycle() {
        let input = makeInput(frame: TonalFrame(scale: .minor, root: Root(0)!))

        var adopted = Pattern()
        for index in 0..<Pattern.trackCount {
            let frame = TonalFrame(scale: .major, root: Root(index % 12)!)
            adopted = adopted.replacing(
                Cycle(shape: Shape(steps: Steps(8)!, pulses: Pulses(3)!), frame: frame),
                at: index
            )
        }

        input.adopt(adopted)

        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(
                input.pattern.cycle(at: index)?.frame,
                TonalFrame(scale: .major, root: Root(index % 12)!),
                "Track \(index): se re-sembró el marco"
            )
        }
    }

    // MARK: - Adoptar no publica (FR4)

    /// Quien provoca el cambio ya avisa al transporte; publicar además dejaría
    /// dos publicaciones por cambio y una carrera por cuál gana.
    func testAdoptingDoesNotPublish() {
        let published = Published()
        let input = makeInput(publish: published.record)

        input.adopt(makePattern(steps: 12, pulses: 5, channel: 7))

        XCTAssertEqual(published.count, 0, "adoptar publicó")
    }

    // MARK: - El fallo reportado, escrito como test

    /// **Después de adoptar, un giro de knob edita el material nuevo.** Antes de
    /// este track republicaba el Pattern anterior entero.
    func testATurnAfterAdoptingEditsTheNewMaterialAndNotTheOld() {
        let published = Published()
        let input = makeInput(publish: published.record)

        // Trabajo sobre el Bank viejo: un pool y un Shape reconocibles.
        input.receive(pad(0))
        input.receive(knob(ControlMapping.beatStepPro.controller(for: .steps)!, delta: 3))
        let old = input.pattern

        // Se cambia de Bank a uno vacío.
        input.adopt(Pattern())
        XCTAssertTrue(
            input.receive(knob(ControlMapping.beatStepPro.controller(for: .pulses)!, delta: 1)))

        let last = published.last!
        XCTAssertNotEqual(last, old, "volvió el Pattern anterior")
        XCTAssertTrue(last.cycle(at: 0)!.pool.isEmpty, "resucitó el pool del Bank anterior")
        XCTAssertEqual(
            last.cycle(at: 0)?.shape.steps,
            Pattern().cycle(at: 0)?.shape.steps,
            "volvieron los Steps del Bank anterior"
        )
    }

    // MARK: - Helpers

    private func makeInput(
        frame: TonalFrame = TonalFrame(scale: .minor, root: Root(0)!),
        publish: @escaping @Sendable (Pattern) -> Void = { _ in }
    ) -> ControlInput {
        ControlInput(pattern: Pattern(), frame: frame, publish: publish)
    }

    private func makePattern(steps: Int, pulses: Int, channel: Int) -> Pattern {
        var pattern = Pattern()
        for index in 0..<Pattern.trackCount {
            pattern = pattern.replacing(
                Cycle(
                    shape: Shape(steps: Steps(steps)!, pulses: Pulses(pulses)!),
                    channel: Channel(channel)!
                ),
                at: index
            )
        }
        return pattern
    }

    private func pad(_ index: Int) -> MIDIMessage {
        .noteOn(
            channel: MIDIChannel(1)!,
            note: MIDINote(Int(ControlMapping.defaultPadBlock.value) + index)!,
            velocity: MIDIVelocity(100)!
        )
    }

    private func knob(_ controller: MIDIController, delta: Int) -> MIDIMessage {
        .controlChange(
            channel: MIDIChannel(1)!,
            controller: controller,
            value: UInt8(delta > 0 ? delta : 128 + delta)
        )
    }
}
