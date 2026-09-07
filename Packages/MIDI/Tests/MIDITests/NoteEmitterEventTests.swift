import Engine
import XCTest

@testable import MIDI

/// Tests de la emisión con velocity y gate **del evento**, no del Groove.
///
/// **El Pulse y sus repeticiones tienen que viajar por el mismo camino.** Una
/// repetición suena a la velocity que le da la rampa y dura su propio hueco, así
/// que el emisor deja de deducir las dos cosas del `Groove` y pasa a recibirlas.
/// Un camino aparte para las repeticiones duplicaría la regla del note-off, que
/// es la que evita notas colgadas — y duplicarla es cómo se cuelgan.
///
/// **La vía de hoy no cambia** (FR16): la firma con `groove` sigue existiendo,
/// calcula la velocity y el gate igual que siempre y llama a la de abajo.
final class NoteEmitterEventTests: XCTestCase {

    private let emitter = NoteEmitter()
    private let channel = MIDIChannel(1)!
    private let stepNanoseconds: Int64 = 25_000_000

    private func emitted(
        velocity: Velocity,
        gateNanoseconds: Int64,
        atHostTime hostTime: UInt64 = 1_000
    ) -> [(message: MIDIMessage, hostTime: UInt64)] {
        var sent: [(message: MIDIMessage, hostTime: UInt64)] = []
        emitter.emit(
            pitch: Pitch(48)!,
            velocity: velocity,
            gateNanoseconds: gateNanoseconds,
            on: channel,
            atHostTime: hostTime
        ) { message, time in
            sent.append((message, time))
        }
        return sent
    }

    private func emittedFromGroove(
        _ groove: Groove,
        atHostTime hostTime: UInt64 = 1_000
    ) -> [(message: MIDIMessage, hostTime: UInt64)] {
        var sent: [(message: MIDIMessage, hostTime: UInt64)] = []
        emitter.emit(
            pitch: Pitch(48)!,
            groove: groove,
            on: channel,
            stepDurationNanoseconds: stepNanoseconds,
            atHostTime: hostTime
        ) { message, time in
            sent.append((message, time))
        }
        return sent
    }

    // MARK: - La velocity es la del evento

    func testTheNoteOnCarriesTheVelocityItIsGiven() {
        let sent = emitted(velocity: Velocity(37)!, gateNanoseconds: 10_000_000)

        guard case .noteOn(_, _, let velocity) = sent.first?.message else {
            return XCTFail("no hubo note-on")
        }
        XCTAssertEqual(velocity.value, 37)
    }

    /// Y no la del Groove: emitir con una velocity distinta de la del Groove
    /// produce **esa**.
    func testTheEventVelocityWinsOverTheGrooveDefault() {
        let sent = emitted(velocity: Velocity(1)!, gateNanoseconds: 10_000_000)

        guard case .noteOn(_, _, let velocity) = sent.first?.message else {
            return XCTFail("no hubo note-on")
        }
        XCTAssertNotEqual(velocity.value, UInt8(Groove.default.velocity.value))
        XCTAssertEqual(velocity.value, 1)
    }

    /// **El note-off sigue con velocity 0.** Es la convención de apagado de
    /// MIDI 1.0 y no depende de con cuánta fuerza sonó la nota.
    func testTheNoteOffKeepsVelocityZero() {
        let sent = emitted(velocity: Velocity(127)!, gateNanoseconds: 10_000_000)

        guard case .noteOff(_, _, let velocity) = sent.last?.message else {
            return XCTFail("no hubo note-off")
        }
        XCTAssertEqual(velocity.value, 0)
    }

    // MARK: - El gate es el del evento

    /// El note-off se sella a la distancia que se pide, **sin volver a mirar el
    /// Step**.
    func testTheNoteOffIsSealedAtTheGivenGate() {
        let gate: Int64 = 3_000_000
        let sent = emitted(velocity: Velocity(100)!, gateNanoseconds: gate, atHostTime: 5_000)

        XCTAssertEqual(
            sent.last?.hostTime,
            5_000 &+ HostClock.hostTicks(fromNanoseconds: UInt64(gate))
        )
    }

    /// Dos gates distintos sellan dos instantes distintos: es lo que permite que
    /// cada repetición dure lo suyo.
    func testTwoGatesSealTwoDifferentInstants() {
        let short = emitted(velocity: Velocity(100)!, gateNanoseconds: 1_000_000)
        let long = emitted(velocity: Velocity(100)!, gateNanoseconds: 9_000_000)

        XCTAssertLessThan(short.last!.hostTime, long.last!.hostTime)
    }

    /// Un gate negativo no puede sellar el note-off antes del note-on: se acota
    /// en cero, como ya hacía el cálculo desde Sustain.
    func testANegativeGateNeverSealsBeforeTheNoteOn() {
        let sent = emitted(velocity: Velocity(100)!, gateNanoseconds: -5_000_000, atHostTime: 800)

        XCTAssertEqual(sent.last?.hostTime, 800)
    }

    /// Sin altura no se emite nada, como en la vía de siempre.
    func testWithoutAPitchNothingIsEmitted() {
        var sent = 0
        emitter.emit(
            pitch: nil,
            velocity: Velocity(100)!,
            gateNanoseconds: 10_000_000,
            on: channel,
            atHostTime: 1_000
        ) { _, _ in sent += 1 }

        XCTAssertEqual(sent, 0)
    }

    // MARK: - FR16: la vía de hoy no cambia

    /// **Un Pulse sin repeticiones emite exactamente el mismo par de mensajes**
    /// que antes de la rebanada: la Velocity del Groove y el gate de Sustain
    /// sobre el Step.
    func testTheGroovePathEmitsTheSamePairAsBefore() {
        let groove = Groove(
            velocity: Velocity(90)!,
            sustain: Sustain(percent: 50)!,
            probability: .default
        )
        let fromGroove = emittedFromGroove(groove)
        let fromEvent = emitted(
            velocity: Velocity(90)!,
            gateNanoseconds: groove.sustain.gateNanoseconds(forStep: stepNanoseconds)
        )

        XCTAssertEqual(fromGroove.count, 2)
        XCTAssertEqual(fromGroove.map(\.hostTime), fromEvent.map(\.hostTime))
        XCTAssertEqual(fromGroove.map(\.message), fromEvent.map(\.message))
    }

    /// Y recorriendo el Sustain entero, que es donde se vería un redondeo que se
    /// hubiera movido de sitio.
    func testTheGroovePathMatchesTheEventPathAcrossSustain() {
        for percent in [1, 25, 50, 100, 150, 200] {
            let groove = Groove(
                velocity: Velocity(64)!,
                sustain: Sustain(percent: percent)!,
                probability: .default
            )
            let fromGroove = emittedFromGroove(groove)
            let fromEvent = emitted(
                velocity: Velocity(64)!,
                gateNanoseconds: groove.sustain.gateNanoseconds(forStep: stepNanoseconds)
            )

            XCTAssertEqual(fromGroove.map(\.hostTime), fromEvent.map(\.hostTime), "\(percent)%")
        }
    }
}
