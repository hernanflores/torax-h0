import XCTest

@testable import Engine

/// Ver la nota de `PatternTests`: `Pattern` a secas es ambiguo en un target de
/// test, porque XCTest arrastra el `Pattern` de Quickdraw.
private typealias Pattern = Engine.Pattern

/// Tests del `Track` que contiene Cycles.
///
/// **El nivel nuevo.** Hasta la v2 el Track *era* el juego de parámetros; desde
/// esta rebanada lo **contiene**: hasta dieciséis Cycles, cuántos están activos y
/// por cuál va la reproducción. Lo que se comprueba aquí es la contención y el
/// almacenamiento —que sigue siendo trivial y de tamaño fijo—, no el recorrido,
/// que es una función pura y se testea aparte.
final class TrackTests: XCTestCase {

    private func cycle(pulses: Int = 5, pitch: Int = 48) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: PitchPool().inserting(Pitch(pitch)!)
        )
    }

    // MARK: - Cómo arranca

    /// **FR10 — con un Cycle activo, todo suena como hoy.** Un Track recién
    /// construido tiene dieciséis Cycles, **uno solo activo** y el cursor en el
    /// primero: exactamente el comportamiento anterior a esta rebanada, que es
    /// lo que hace que meter el nivel no cambie lo que se oye.
    func testANewTrackHasSixteenCyclesOneActiveAndTheCursorAtTheFirst() {
        let track = Track(cycle())

        XCTAssertEqual(Track.cycleCount, 16)
        XCTAssertEqual(track.activeCount, 1, "arrancó con más de un Cycle activo")
        XCTAssertEqual(track.cursor, 0, "el cursor no arrancó en el primero")
        XCTAssertEqual(track.current, cycle(), "lo que suena no es el Cycle con el que se creó")
    }

    /// Los dieciséis existen desde el principio, como los dieciséis Tracks del
    /// Pattern: no hay Cycles que crear ni destruir, solo cuántos se recorren.
    func testTheSixteenCyclesExistFromTheStart() {
        let track = Track(cycle())

        for index in 0..<Track.cycleCount {
            XCTAssertNotNil(track.cycle(at: index), "el Cycle \(index + 1) no existe")
        }
    }

    // MARK: - El almacenamiento

    /// **La restricción que no se puede perder.** El Track viaja en el snapshot
    /// que el hilo del scheduler copia una vez por ventana, así que copiarlo no
    /// puede tocar el conteo de referencias: un `retain` ahí es una violación de
    /// las reglas de tiempo real.
    ///
    /// Es lo que obliga al almacenamiento inline y de tamaño fijo, por la misma
    /// razón que en `PitchPool` y en `Pattern`.
    func testTheTrackAndThePatternAreStillTrivialTypes() {
        XCTAssertTrue(_isPOD(Track.self), "el Track con Cycles dentro dejó de ser trivial")
        XCTAssertTrue(_isPOD(Pattern.self), "el Pattern dejó de ser trivial con el nivel nuevo")
        XCTAssertTrue(_isPOD(Cycle.self))
    }

    /// El tamaño es el de dieciséis Cycles más los dos contadores, y nada más.
    ///
    /// La cifra que decidió el diseño está medida en `CycleSnapshotCostTests`;
    /// esto solo vigila que el tipo no gane un campo por descuido.
    func testTheTrackIsSixteenCyclesAndTwoCounters() {
        XCTAssertEqual(
            MemoryLayout<Track>.size,
            MemoryLayout<Cycle>.size * 16 + MemoryLayout<Int>.size * 2)
        XCTAssertEqual(MemoryLayout<Pattern>.size, MemoryLayout<Track>.size * 16)
    }

    // MARK: - Sustituir un Cycle

    /// Sustituir uno devuelve un Track nuevo con **solo ese** cambiado. Se
    /// comprueba sobre los otros quince, que es donde se vería el fallo: un
    /// `replacing` que escribiera de más no lo delataría mirando solo el que se
    /// tocó.
    func testReplacingOneCycleLeavesTheOtherFifteenUntouched() {
        let original = cycle()
        let track = Track(original)
        let edited = track.replacing(cycle(pulses: 9), at: 4)

        XCTAssertEqual(edited.cycle(at: 4), cycle(pulses: 9))
        for index in 0..<Track.cycleCount where index != 4 {
            XCTAssertEqual(edited.cycle(at: index), original, "cambió el Cycle \(index + 1)")
        }
    }

    /// Y no toca los contadores: sustituir material no es moverse por él.
    func testReplacingACycleDoesNotMoveTheCountersOrTheCursor() {
        let track = Track(cycle()).replacing(cycle(pulses: 9), at: 7)

        XCTAssertEqual(track.activeCount, 1)
        XCTAssertEqual(track.cursor, 0)
    }

    /// Sustituir el que suena es el caso de la edición en caliente: cambia lo
    /// que se oye y nada más.
    func testReplacingTheCurrentCycleChangesWhatSounds() {
        let track = Track(cycle()).replacingCurrent(cycle(pulses: 12))

        XCTAssertEqual(track.current, cycle(pulses: 12))
        XCTAssertEqual(track.cycle(at: 1), cycle(), "tocó un Cycle que no era el vigente")
    }

    // MARK: - Fuera de rango

    /// Leer fuera de 0–15 devuelve `nil` y no revienta: el mismo criterio que un
    /// pad fuera de la superficie. Lo puede preguntar el hilo del scheduler, y
    /// ahí un `fatalError` sería un fallo de audio, no un error de programación
    /// visible.
    func testReadingACycleOutOfRangeIsNilAndNotACrash() {
        let track = Track(cycle())

        XCTAssertNil(track.cycle(at: -1))
        XCTAssertNil(track.cycle(at: 16))
        XCTAssertNil(track.cycle(at: Int.max))
    }

    /// Y escribir fuera de rango devuelve el Track tal cual, con el mismo
    /// criterio: nada que cambiar, nada que romper.
    func testReplacingOutOfRangeLeavesTheTrackAsItWas() {
        let track = Track(cycle())

        XCTAssertEqual(track.replacing(cycle(pulses: 9), at: -1), track)
        XCTAssertEqual(track.replacing(cycle(pulses: 9), at: 16), track)
    }

    // MARK: - Igualdad

    /// La igualdad mira los dieciséis Cycles y los dos contadores. Sin esto, dos
    /// Tracks con material distinto en el Cycle 12 se compararían iguales y el
    /// Pattern heredaría el fallo.
    func testEqualityLooksAtEveryCycleAndBothCounters() {
        let track = Track(cycle())

        XCTAssertEqual(track, Track(cycle()))
        XCTAssertNotEqual(track, track.replacing(cycle(pulses: 9), at: 12))
    }
}
