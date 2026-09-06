import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Tests de las vías táctiles que callan con Ctrl All hundido (FR11).
///
/// **Es un requisito que Temp no tiene, y la asimetría es deliberada.** Los dos
/// gestos prometen no escribir en el Pattern, pero Temp acota su promesa a un
/// Track y a los parámetros que la mano toca; Ctrl All la extiende a los doce.
/// Una escritura colada por la pantalla mientras el desplazamiento está puesto
/// **no se deshace al soltar**, porque el snapshot no la guarda:
///
/// - `setFrame(_:)` reencuadra el pool del Track, y el pool no está en el
///   snapshot.
/// - `setActiveCycleCount(_:)` activa Cycles que no tienen base guardada — se
///   quedarían con el desplazamiento puesto para siempre.
/// - `setChannel(_:)` y su variante por Track cambian por dónde sale la voz.
/// - `selectTrack(_:)` mueve lo que la pantalla enseña con el gesto en curso.
///
/// **No se prueba que sean imposibles, sino que devuelven `false` y no
/// publican**, con el mismo criterio que un CC sin asignar: en una sesión real
/// llega de todo y nada de esto es un error.
final class CtrlAllTouchPathTests: XCTestCase {

    private final class Published: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var count = 0

        func record(_ pattern: Pattern) {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    // MARK: - Las cinco callan

    func testSelectTrackIsIgnored() {
        let (input, published) = makeInput()
        input.receive(ctrlAll())

        XCTAssertFalse(input.selectTrack(7))

        XCTAssertEqual(input.selectedTrackIndex, 0, "cambió de Track con el gesto puesto")
        XCTAssertEqual(published.count, 0)
    }

    func testSetChannelIsIgnored() {
        let (input, published) = makeInput()
        let channel = input.track.channel
        input.receive(ctrlAll())

        XCTAssertFalse(input.setChannel(Channel(9)!))

        XCTAssertEqual(input.track.channel, channel)
        XCTAssertEqual(published.count, 0)
    }

    func testSetChannelForATrackIsIgnored() {
        let (input, published) = makeInput()
        let channel = input.pattern.editingCycle(at: 3)!.channel
        input.receive(ctrlAll())

        XCTAssertFalse(input.setChannel(Channel(9)!, forTrack: 3))

        XCTAssertEqual(input.pattern.editingCycle(at: 3)?.channel, channel)
        XCTAssertEqual(published.count, 0)
    }

    /// **El que más importa de los cinco:** un cambio de Scale reencuadra el pool
    /// y el pool no está en el snapshot, así que soltar no lo desharía.
    func testSetFrameIsIgnored() {
        let (input, published) = makeInput()
        let frame = input.frame
        let pool = input.track.pool
        input.receive(ctrlAll())

        XCTAssertFalse(input.setFrame(TonalFrame(scale: .major, root: Root(6)!)))

        XCTAssertEqual(input.frame, frame, "el marco tonal cambió con el gesto puesto")
        XCTAssertEqual(input.track.pool, pool, "el pool se reencuadró y no se desharía al soltar")
        XCTAssertEqual(published.count, 0)
    }

    /// **El que rompería la restauración:** un Cycle activado a media
    /// superposición no tiene base guardada.
    func testSetActiveCycleCountIsIgnored() {
        let (input, published) = makeInput()
        input.receive(ctrlAll())

        XCTAssertFalse(input.setActiveCycleCount(4))

        XCTAssertEqual(input.pattern.track(at: 0)?.activeCount, 1)
        XCTAssertEqual(published.count, 0)
    }

    // MARK: - El caso que motiva la regla

    /// Con el desplazamiento puesto, subir el número de Cycles por la pantalla no
    /// puede dejar un Cycle desplazado y sin base: al soltar, el Pattern vuelve
    /// entero.
    func testACycleCannotBeLeftDisplacedWithoutABase() {
        let (input, _) = makeInput()
        let before = input.pattern

        input.receive(ctrlAll())
        input.receive(knob(.pulses, by: 2))
        XCTAssertFalse(input.setActiveCycleCount(4))
        input.receive(ctrlAll(value: 0))

        XCTAssertEqual(input.pattern, before, "quedó algo escrito tras soltar")
    }

    // MARK: - Fuera del hold, las cinco funcionan

    /// El corte dura lo que dura el hold: soltar devuelve la pantalla a la
    /// normalidad, y una vía que se quedara apagada sería peor que no haberla
    /// cortado.
    func testAllFiveWorkAgainAfterReleasing() {
        let (input, _) = makeInput()

        input.receive(ctrlAll())
        input.receive(ctrlAll(value: 0))

        XCTAssertTrue(input.selectTrack(7))
        XCTAssertTrue(input.setChannel(Channel(9)!))
        // Canal 11 y no 4: cada Track arranca en el canal de su número, así que
        // pedirle al Track 4 el canal 4 devuelve `false` por ser un no-op, y el
        // test estaría leyendo «sigue bloqueado» donde dice «ya estaba ahí».
        XCTAssertTrue(input.setChannel(Channel(11)!, forTrack: 3))
        XCTAssertTrue(input.setFrame(TonalFrame(scale: .major, root: Root(6)!)))
        XCTAssertTrue(input.setActiveCycleCount(4))
    }

    /// **Y con Temp hundido siguen funcionando**, que es la asimetría escrita: el
    /// requisito es de Ctrl All y no de los modificadores en general.
    func testTempDoesNotFreezeTheTouchPath() {
        let (input, _) = makeInput()

        input.receive(temp())

        XCTAssertTrue(input.selectTrack(7), "Temp congeló una vía táctil que no le toca")
    }

    // MARK: - Helpers

    private func makeInput() -> (ControlInput, Published) {
        let published = Published()
        let input = ControlInput(
            track: Cycle(
                shape: Shape(steps: Steps(8)!, pulses: Pulses(4)!),
                pool: PitchPool().inserting(Pitch(48)!)
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
