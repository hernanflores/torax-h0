import XCTest

@testable import Engine

/// Tests de Pitch dentro del `Cycle`: el offset en grados y el pool que suena
/// (`pitch-harmony_20260912`, FR1, FR2, FR4, FR7, NFR1).
///
/// **Los pads editan el pool; lo que suena es el pool transpuesto.** El `Cycle`
/// guarda los dos: el pool base, que es material del usuario y no se toca, y el
/// pool que suena, derivado al construirse. Así el hilo del scheduler sigue
/// leyendo un `PitchPool` inline sin hacer aritmética de grados.
final class PitchOffsetInCycleTests: XCTestCase {

    private let shape = Shape(steps: Steps(16)!, pulses: Pulses(16)!)
    private let cMajor = TonalFrame(scale: .major, root: .c)

    private func pool(_ values: [Int]) -> PitchPool {
        values.reduce(PitchPool()) { $0.inserting(Pitch($1)!) }
    }

    private func values(_ pool: PitchPool) -> [Int] {
        (0..<pool.count).compactMap { pool.pitch(at: $0)?.value }
    }

    // MARK: - El tipo

    /// ±28 grados: unas cuatro octavas en una escala de siete notas (FR5).
    func testTheOffsetIsBoundedToTwentyEightDegrees() {
        XCTAssertEqual(PitchOffset.validRange, -28...28)
        XCTAssertNotNil(PitchOffset(28))
        XCTAssertNotNil(PitchOffset(-28))
        XCTAssertNil(PitchOffset(29))
        XCTAssertNil(PitchOffset(-29))
        XCTAssertEqual(PitchOffset.zero.degrees, 0)
    }

    /// **Un byte por Cycle**, en el idioma de `NoteRepeater` y `Modulation`.
    func testTheOffsetCostsOneByte() {
        XCTAssertEqual(MemoryLayout<PitchOffset>.size, 1)
    }

    // MARK: - El default

    /// Un Cycle recién creado no transpone, y lo que suena es el pool (AC 11).
    func testAFreshCycleSoundsItsPool() {
        let cycle = Cycle(shape: shape, pool: pool([60, 64, 67]), frame: cMajor)
        XCTAssertEqual(cycle.pitchOffset, .zero)
        XCTAssertEqual(cycle.soundingPool, cycle.pool)
    }

    /// Con offset 0 lo que suena es el pool, en todos los marcos, **aunque el
    /// pool tenga alturas fuera del marco**: el camino nuevo no reencuadra nada
    /// que antes no se reencuadrara.
    func testZeroOffsetSoundsThePoolVerbatimInEveryFrame() {
        let chromatic = pool([60, 61, 62, 63, 64, 65, 66, 67])
        for scale in Scale.allCases {
            for root in Root.validRange {
                let cycle = Cycle(
                    shape: shape, pool: chromatic,
                    frame: TonalFrame(scale: scale, root: Root(root)!))
                XCTAssertEqual(cycle.soundingPool, chromatic, "\(scale)·\(root)")
            }
        }
    }

    // MARK: - Transponer

    /// C4 E4 G4 en Do mayor: +1 da D4 F4 A4 y −1 da B3 D4 F4 (AC 1).
    func testTheTriadExampleOfThePRD() {
        let cycle = Cycle(shape: shape, pool: pool([60, 64, 67]), frame: cMajor)

        XCTAssertEqual(values(cycle.with(pitchOffset: PitchOffset(1)!).soundingPool), [62, 65, 69])
        XCTAssertEqual(
            values(cycle.with(pitchOffset: PitchOffset(-1)!).soundingPool), [59, 62, 65])
        XCTAssertEqual(values(cycle.with(pitchOffset: PitchOffset(2)!).soundingPool), [64, 67, 71])
    }

    /// **El pool base no se toca**: transponer no es editar material (FR7).
    func testTransposingKeepsTheBasePool() {
        let base = pool([60, 64, 67])
        let cycle = Cycle(shape: shape, pool: base, frame: cMajor).with(
            pitchOffset: PitchOffset(3)!)
        XCTAssertEqual(cycle.pool, base)
    }

    /// Volver a 0 devuelve exactamente el pool.
    func testReturningToZeroRestoresThePool() {
        let cycle = Cycle(shape: shape, pool: pool([60, 64, 67]), frame: cMajor)
        let back = cycle.with(pitchOffset: PitchOffset(5)!).with(pitchOffset: .zero)
        XCTAssertEqual(back, cycle)
    }

    /// El recorrido del pool sale del pool que suena.
    func testPitchAtStepWalksTheSoundingPool() {
        let cycle = Cycle(shape: shape, pool: pool([60, 64, 67]), frame: cMajor)
            .with(pitchOffset: PitchOffset(1)!)
        XCTAssertEqual((0..<3).map { cycle.pitch(atStep: $0)?.value }, [62, 65, 69])
    }

    /// **Pitch conserva los intervalos en grados** entre todos los pares (AC 7),
    /// en todas las escalas y Roots y en todo el rango, mientras quepa en MIDI.
    func testTransposingPreservesDegreeIntervals() throws {
        for scale in Scale.allCases {
            for root in Root.validRange {
                let frame = TonalFrame(scale: scale, root: Root(root)!)
                let base = PitchPool()
                    .inserting(frame.nearest(to: Pitch(55)!))
                    .inserting(frame.nearest(to: Pitch(60)!))
                    .inserting(frame.nearest(to: Pitch(66)!))
                let cycle = Cycle(shape: shape, pool: base, frame: frame)
                let baseDegrees = try (0..<base.count).map {
                    try XCTUnwrap(frame.degree(of: base.pitch(at: $0)!))
                }

                for offset in PitchOffset.validRange
                where baseDegrees.allSatisfy({ frame.pitch(atDegree: $0 + offset) != nil }) {
                    let sounding = cycle.with(pitchOffset: PitchOffset(offset)!).soundingPool
                    XCTAssertEqual(sounding.count, base.count, "\(scale)·\(root)·\(offset)")
                    let degrees = try (0..<sounding.count).map {
                        try XCTUnwrap(frame.degree(of: sounding.pitch(at: $0)!))
                    }
                    XCTAssertEqual(
                        zip(degrees, baseDegrees).map { $0 - $1 },
                        Array(repeating: offset, count: base.count),
                        "\(scale)·\(root)·\(offset)")
                }
            }
        }
    }

    /// **Una altura del pool fuera del marco se transpone desde la más cercana**,
    /// con el mismo desempate que el reencuadre. No es alcanzable desde los pads
    /// —que solo dan grados del marco— pero un proyecto guardado puede traerla.
    func testAPoolPitchOutsideTheFrameTransposesFromItsNearest() {
        let cycle = Cycle(shape: shape, pool: pool([61]), frame: cMajor)  // C#4
            .with(pitchOffset: PitchOffset(1)!)
        XCTAssertEqual(values(cycle.soundingPool), [62], "C#4 se lee C4, y un grado arriba es D4")
    }

    /// **Lo que no cabe en MIDI se queda en la última altura del marco dentro
    /// del rango.** No es alcanzable con el knob, que se frena antes (FR6), pero
    /// un cambio de Scale que conserva Pitch sí puede llevar ahí. El pool que
    /// suena nunca emite fuera de 0–127 (FR3).
    func testWhatDoesNotFitInMIDIStaysAtTheEdgeOfTheFrame() {
        let high = Cycle(shape: shape, pool: pool([124]), frame: cMajor)  // E9
            .with(pitchOffset: PitchOffset(28)!)
        XCTAssertEqual(values(high.soundingPool), [127], "G9 es la última de Do mayor")

        let low = Cycle(shape: shape, pool: pool([2]), frame: cMajor)  // D-1
            .with(pitchOffset: PitchOffset(-28)!)
        XCTAssertEqual(values(low.soundingPool), [0])
    }

    // MARK: - Editar y seguir siendo trivial

    /// `with(...)` conserva el offset en cualquier otra edición.
    func testOtherEditsKeepTheOffset() {
        let cycle = Cycle(shape: shape, pool: pool([60, 64, 67]), frame: cMajor)
            .with(pitchOffset: PitchOffset(2)!)

        XCTAssertEqual(cycle.with(channel: Channel(3)!).pitchOffset, PitchOffset(2))
        XCTAssertEqual(cycle.with(padOctaveShift: 1).pitchOffset, PitchOffset(2))
        XCTAssertEqual(cycle.with(groove: .default).pitchOffset, PitchOffset(2))
        for parameter in TrackParameter.allCases {
            XCTAssertEqual(
                cycle.applying(1, to: parameter).pitchOffset, PitchOffset(2), "\(parameter)")
        }
    }

    /// Cambiar el pool o el marco rederiva lo que suena con el mismo offset.
    func testChangingThePoolOrTheFrameRederivesTheSoundingPool() {
        let cycle = Cycle(shape: shape, pool: pool([60]), frame: cMajor)
            .with(pitchOffset: PitchOffset(1)!)

        XCTAssertEqual(values(cycle.with(pool: pool([64])).soundingPool), [65])
        let aMinor = TonalFrame(scale: .minor, root: Root(9)!)
        XCTAssertEqual(
            values(cycle.with(frame: aMinor).soundingPool), [62], "C4 +1 en La menor es D4")
    }

    /// `_isPOD(Cycle.self)` sigue siendo cierto (NFR1).
    func testTheCycleIsStillTriviallyCopyable() {
        XCTAssertTrue(_isPOD(PitchOffset.self))
        XCTAssertTrue(_isPOD(Cycle.self))
        XCTAssertTrue(_isPOD(Track.self))
        XCTAssertTrue(_isPOD(Engine.Pattern.self))
    }
}
