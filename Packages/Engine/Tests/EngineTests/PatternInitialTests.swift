import XCTest
@testable import Engine

/// Ver la nota de `PatternTests` sobre la ambigüedad del nombre en los targets
/// de test.
private typealias Pattern = Engine.Pattern

/// Tests del Pattern con el que arranca la app.
///
/// **La regla que fijan: una rebanada de motor no cambia lo que se oye.** Al
/// pasar de un Track a varios, la app tiene que sonar exactamente como sonaba
/// —el Track 1 con su material y el resto callados— hasta que alguien use los
/// demás. Vale igual con dieciséis que con doce: por eso los recorridos derivan
/// de `trackCount` y no repiten el número.
final class PatternInitialTests: XCTestCase {

    // MARK: - Solo el Track 1 trae material

    func testOnlyTheFirstTrackHasMaterial() {
        let pattern = Pattern.initial

        XCTAssertFalse(pattern.cycle(at: 0)!.pool.isEmpty, "el Track 1 arrancó mudo")
        for index in 1..<Pattern.trackCount {
            XCTAssertTrue(pattern.cycle(at: index)!.pool.isEmpty, "Track \(index + 1)")
        }
    }

    /// El material es el que la app ya usaba: una sola altura, que la Pre Spec
    /// describe como «centro estable».
    func testTheFirstTrackKeepsTheMaterialTheAppAlreadyHad() {
        let track = Pattern.initial.cycle(at: 0)!

        XCTAssertEqual(track.pool.count, 1)
        XCTAssertTrue(track.pool.contains(Pitch(48)!))
    }

    /// Y el Shape es el mismo 16/5 con el que la app abre: uno de los casos de
    /// la Pre Spec, reconocible de oído.
    func testTheFirstTrackKeepsTheShapeTheAppAlreadyHad() {
        let shape = Pattern.initial.cycle(at: 0)!.shape

        XCTAssertEqual(shape.steps.count, 16)
        XCTAssertEqual(shape.pulses.count, 5)
    }

    // MARK: - Los demás Tracks, vacíos, no suenan

    /// **Un Track vacío no emite aunque dispare.** Es el comportamiento que ya
    /// tenía un Track solo; lo que cambia es que ahora hay varios a la vez, y de
    /// ahí sale que la app arranque sonando igual que antes.
    func testAnEmptyTrackEmitsNothingEvenThoughItTriggers() {
        let pattern = Pattern.initial

        for index in 1..<Pattern.trackCount {
            let track = pattern.cycle(at: index)!
            var triggered = false

            for step in 0..<track.shape.steps.count where track.triggers(atStep: step) {
                triggered = true
                XCTAssertNil(track.pitch(atStep: step), "Track \(index + 1), step \(step)")
            }

            XCTAssertTrue(
                triggered, "el Track \(index + 1) no dispara: el silencio vendría del Shape")
        }
    }

    /// El Track 1 sí emite, que es la otra mitad de la comprobación.
    func testTheFirstTrackDoesEmit() {
        let track = Pattern.initial.cycle(at: 0)!
        let pitches = (0..<track.shape.steps.count)
            .filter { track.triggers(atStep: $0) }
            .compactMap { track.pitch(atStep: $0) }

        XCTAssertEqual(pitches.count, 5, "cinco Pulses, cinco notas")
        XCTAssertTrue(pitches.allSatisfy { $0 == Pitch(48)! })
    }

    // MARK: - Cada Track en su canal

    /// **El Track N emite por el canal N.**
    ///
    /// Es la correspondencia que no hay que explicar, y sin ella los doce
    /// sonarían al mismo instrumento. Se puede cambiar desde la pantalla MIDI:
    /// dos capas rítmicas sobre el mismo sinte es un caso real.
    ///
    /// Con doce Tracks los canales 13–16 dejan de asignarse solos, pero **siguen
    /// siendo elegibles**: el rango de `Channel` es el del protocolo MIDI, no el
    /// de la app.
    func testEachTrackDefaultsToItsOwnChannel() {
        let pattern = Pattern()

        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(
                pattern.cycle(at: index)?.channel.number, index + 1, "Track \(index + 1)")
        }
    }

    /// Y el Pattern inicial no lo cambia: darle material al Track 1 no le mueve
    /// el canal a nadie.
    func testTheInitialPatternKeepsTheDefaultChannels() {
        for index in 0..<Pattern.trackCount {
            XCTAssertEqual(
                Pattern.initial.cycle(at: index)?.channel.number, index + 1,
                "Track \(index + 1)")
        }
    }

    // MARK: - Sigue siendo trivial

    func testTheInitialPatternIsStillATrivialValue() {
        XCTAssertTrue(_isPOD(Pattern.self))
    }
}
