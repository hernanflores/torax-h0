import Engine
import XCTest
@testable import MIDI

/// Tests de la cadena completa: mensaje MIDI → Track publicado.
///
/// Se testea entera sin CoreMIDI y sin hardware. Lo único que falta para que
/// esto sea un instrumento es de dónde llegan los mensajes, que es la fase
/// siguiente.
final class ControlInputTests: XCTestCase {

    private let channel = MIDIChannel(1)!

    private func shape(steps: Int = 16, pulses: Int = 4, division: Division = .sixteenth) -> Shape {
        Shape(steps: Steps(steps)!, pulses: Pulses(pulses)!, division: division)
    }

    private func turn(_ parameter: TrackParameter, by value: UInt8) -> MIDIMessage {
        .controlChange(
            channel: channel,
            controller: ControlMapping.beatStepPro.controller(for: parameter)!,
            value: value
        )
    }

    private func makeInput(_ shape: Shape) -> (ControlInput, TrackHandoff) {
        let handoff = TrackHandoff(Track(shape: shape))
        return (ControlInput(track: Track(shape: shape), publishingTo: handoff), handoff)
    }

    // MARK: - Girar publica

    func testTurningAKnobPublishesANewTrack() {
        let (input, handoff) = makeInput(shape(pulses: 4))

        XCTAssertTrue(input.receive(turn(.pulses, by: 0x01)))

        XCTAssertEqual(input.track.shape.pulses.count, 5)
        XCTAssertEqual(handoff.load()?.track(at: 0)?.shape.pulses.count, 5, "no llegó al scheduler")
    }

    func testTurningBackwardsDecrements() {
        let (input, _) = makeInput(shape(pulses: 4))
        input.receive(turn(.pulses, by: 0x7F))
        XCTAssertEqual(input.track.shape.pulses.count, 3)
    }

    func testAccumulatedTurnsAddUp() {
        let (input, handoff) = makeInput(shape(pulses: 1))
        for _ in 0..<5 { input.receive(turn(.pulses, by: 0x01)) }
        XCTAssertEqual(handoff.load()?.track(at: 0)?.shape.pulses.count, 6)
    }

    /// Cada parámetro responde a su propio controlador.
    ///
    /// Se parte de un Shape con margen en los cuatro: Division arranca en 1/16,
    /// que ya es el extremo rápido, así que subirla desde ahí **debe** no mover
    /// nada — el punto de partida se elige para probar que responde, no para
    /// tapar que frena.
    func testEveryParameterIsReachableFromItsController() {
        for parameter in TrackParameter.allCases {
            let steps = Steps(8)!
            let roomy = Shape(steps: steps, pulses: Pulses(4)!, division: .quarter)
            // **Groove también parte lejos de sus extremos.** Su default deja
            // Probability en el 100%, que es su tope: un giro hacia arriba no
            // movería nada y el test diría que el parámetro no responde cuando
            // lo que pasa es que ya está donde puede estar.
            let roomyGroove = Groove(
                velocity: Velocity(64)!,
                sustain: Sustain(percent: 100)!,
                probability: Probability(percent: 50)!
            )
            let track = Track(shape: roomy, groove: roomyGroove)
            let handoff = TrackHandoff(track)
            let input = ControlInput(track: track, publishingTo: handoff)

            XCTAssertTrue(input.receive(turn(parameter, by: 0x01)), "\(parameter) no respondió")
        }
    }

    /// Y en el extremo, el mismo giro no publica.
    ///
    /// **El extremo se lee del dominio, no se escribe aquí.** Escrito como
    /// `.sixteenth`, este test falló al añadir 1/32 en la rebanada 5 por un
    /// comportamiento que no había cambiado: lo que cambió fue cuál es el
    /// extremo.
    func testAParameterAtItsEndDoesNotRespond() throws {
        let fastest = try XCTUnwrap(Division.fastest)
        let (input, _) = makeInput(shape(division: fastest))

        XCTAssertFalse(input.receive(turn(.division, by: 0x01)))
    }

    // MARK: - Lo que no debe publicar

    /// Un giro nulo no publica: publicar sin cambio haría trabajo y ruido para
    /// nada.
    func testANeutralValueDoesNotPublish() {
        let (input, _) = makeInput(shape(pulses: 4))
        XCTAssertFalse(input.receive(turn(.pulses, by: 0x00)))
        XCTAssertFalse(input.receive(turn(.pulses, by: 0x40)))
        XCTAssertEqual(input.track.shape.pulses.count, 4)
    }

    /// Un controlador sin mapear se ignora en silencio.
    func testAnUnmappedControllerIsIgnored() {
        let (input, _) = makeInput(shape(pulses: 4))
        let unmapped = MIDIMessage.controlChange(
            channel: channel, controller: MIDIController(7)!, value: 0x01
        )
        XCTAssertFalse(input.receive(unmapped))
        XCTAssertEqual(input.track.shape.pulses.count, 4)
    }

    /// Los mensajes de nota **no mueven el Shape**.
    ///
    /// Desde Tonal sí hacen algo —editan el pool, y eso lo cubre
    /// `PadPoolInputTests`—, pero son capas distintas del motor: un pad no puede
    /// mover Steps ni Pulses, igual que un knob de Shape no puede tocar el pool.
    func testNoteMessagesDoNotMoveTheShape() {
        let (input, _) = makeInput(shape(pulses: 4))
        let note = MIDIMessage.noteOn(
            channel: channel, note: MIDINote(60)!, velocity: MIDIVelocity(100)!)
        input.receive(note)
        XCTAssertEqual(input.track.shape.pulses.count, 4)
    }

    /// Girar contra un extremo no publica: el valor ya estaba ahí.
    func testTurningAgainstAnEndDoesNotPublish() {
        let (input, _) = makeInput(shape(pulses: 16))
        XCTAssertFalse(input.receive(turn(.pulses, by: 0x01)))
    }

    // MARK: - La propiedad que motivó el track

    /// De extremo a extremo, desde los mensajes: bajar Steps por debajo de
    /// Pulses y volver a subirlo no cuesta la configuración.
    func testTurningStepsDownAndBackUpIsLosslessFromMessages() {
        let (input, handoff) = makeInput(shape(steps: 16, pulses: 12))

        for _ in 0..<12 { input.receive(turn(.steps, by: 0x7F)) }
        XCTAssertEqual(input.track.shape.steps.count, 4)
        XCTAssertEqual(input.track.shape.effectivePulses, 4, "sonaron más de los que caben")
        XCTAssertEqual(input.track.shape.pulses.count, 12, "el giro destruyó Pulses")

        for _ in 0..<12 { input.receive(turn(.steps, by: 0x01)) }
        XCTAssertEqual(handoff.load()?.track(at: 0)?.shape, shape(steps: 16, pulses: 12))
    }

    // MARK: - Extremos

    /// Un giro grande de golpe se acota, no desborda.
    func testALargeSingleTurnIsClamped() {
        let (input, _) = makeInput(shape(pulses: 1))
        input.receive(turn(.pulses, by: 0x3F))
        XCTAssertEqual(input.track.shape.pulses.count, 16)
    }
}
