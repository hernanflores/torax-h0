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

    /// El tamaño es el de dieciséis Cycles, cuántos hay activos y los dos
    /// cursores, y nada más.
    ///
    /// La cifra que decidió el diseño está medida en `CycleSnapshotCostTests`
    /// —sobre un tipo de prueba con dos contadores, 36 992 bytes de Pattern—; el
    /// tipo real lleva tres y sale a 37 248, un 0,7% más. No mueve la decisión ni
    /// un orden de magnitud. Esto solo vigila que no gane un campo por descuido.
    func testTheTrackIsSixteenCyclesAndThreeCounters() {
        XCTAssertEqual(
            MemoryLayout<Track>.size,
            MemoryLayout<Cycle>.size * 16 + MemoryLayout<Int>.size * 3)
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

/// Tests de cuántos Cycles se recorren, y de qué pasa al mover ese número.
///
/// **Es configuración, no material** (FR2): se ajusta en pantalla, como Scale,
/// Root y el canal. Lo que se fija aquí son las tres reglas que lo rodean —el
/// rango, qué material recibe un Cycle que empieza a existir, y qué pasa con los
/// dos cursores al bajar el número— porque las tres son sitios donde una
/// implementación razonable puede destruir trabajo del usuario.
final class TrackActiveCountTests: XCTestCase {

    private func cycle(pulses: Int) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: PitchPool().inserting(Pitch(48)!)
        )
    }

    // MARK: - El rango

    /// De 1 a 16, y **se frena en los extremos** en vez de envolver: el mismo
    /// criterio que Steps y Division, y el contrario que Rotate. Envolver aquí
    /// convertiría un giro de más en un salto de dieciséis Cycles a uno.
    func testTheRangeIsOneToSixteenAndStopsAtBothEnds() {
        let track = Track(cycle(pulses: 5))

        XCTAssertEqual(track.withActiveCount(0).activeCount, 1)
        XCTAssertEqual(track.withActiveCount(-4).activeCount, 1)
        XCTAssertEqual(track.withActiveCount(17).activeCount, 16)
        XCTAssertEqual(track.withActiveCount(Int.max).activeCount, 16)
        XCTAssertEqual(track.withActiveCount(7).activeCount, 7)
    }

    // MARK: - Subir el número

    /// **FR3 — el que empieza a existir nace copiando el Cycle en edición**, no
    /// vacío ni por defecto. Es lo que hace que A/B/C se construya tocando: se
    /// duplica lo que se está editando y se le cambia una cosa.
    func testRaisingTheCountCopiesTheEditingCycleIntoTheOneThatStartsExisting() {
        let track = Track(cycle(pulses: 5)).withActiveCount(2)

        XCTAssertEqual(track.cycle(at: 1), cycle(pulses: 5), "el Cycle nuevo no nació copiado")
    }

    /// Y el copiado **suena igual hasta que se edita**: si naciera por defecto,
    /// subir el número metería un cambio audible que nadie pidió.
    func testTheCopiedCycleSoundsTheSameUntilItIsEdited() {
        let edited = Track(cycle(pulses: 5)).replacingCurrent(cycle(pulses: 11))
        let grown = edited.withActiveCount(2)

        XCTAssertEqual(grown.cycle(at: 0), grown.cycle(at: 1))
    }

    /// Subir varios de golpe copia en todos los que empiezan a existir, no solo
    /// en el primero: dejar los otros con material viejo sería entregar un
    /// desarrollo que nadie construyó.
    func testRaisingSeveralAtOnceCopiesIntoEveryNewSlot() {
        let track = Track(cycle(pulses: 5)).withActiveCount(4)

        for index in 1..<4 {
            XCTAssertEqual(track.cycle(at: index), cycle(pulses: 5), "el Cycle \(index + 1)")
        }
    }

    /// Se copia el Cycle **en edición**, no el primero ni el que suena. Es la
    /// diferencia que se nota trabajando: se duplica lo que se tiene delante.
    func testItIsTheEditingCycleThatGetsCopiedAndNotTheFirstOne() {
        let track =
            Track(cycle(pulses: 5))
            .withActiveCount(2)
            .replacing(cycle(pulses: 13), at: 1)
            .withEditing(1)
            .withActiveCount(3)

        XCTAssertEqual(track.cycle(at: 2), cycle(pulses: 13))
    }

    // MARK: - Bajar el número

    /// Bajar descarta **por el final**: los que se van son los últimos, no los
    /// primeros. Descartar por delante renumeraría el desarrollo entero.
    func testLoweringDiscardsFromTheEnd() {
        let track =
            Track(cycle(pulses: 5))
            .withActiveCount(4)
            .replacing(cycle(pulses: 13), at: 3)
            .withActiveCount(2)

        XCTAssertEqual(track.activeCount, 2)
        XCTAssertEqual(track.cycle(at: 0), cycle(pulses: 5))
        XCTAssertEqual(track.cycle(at: 1), cycle(pulses: 5))
    }

    /// **FR9 — el Cycle en edición se acota de inmediato** si queda fuera. Eso
    /// sí es pantalla y no sonido: dejarlo apuntando fuera del rango mostraría y
    /// editaría un Cycle que ya no se recorre.
    func testLoweringClampsTheEditingCycleImmediately() {
        let track =
            Track(cycle(pulses: 5))
            .withActiveCount(6)
            .withEditing(5)
            .withActiveCount(2)

        XCTAssertEqual(track.editing, 1, "el Cycle en edición se quedó fuera del rango")
    }

    /// Y el que ya estaba dentro no se mueve: acotar no es reiniciar.
    func testLoweringLeavesTheEditingCycleAloneWhenItStillFits() {
        let track =
            Track(cycle(pulses: 5))
            .withActiveCount(6)
            .withEditing(1)
            .withActiveCount(4)

        XCTAssertEqual(track.editing, 1)
    }

    /// **Bajar no toca el cursor de reproducción** (FR9). De eso se encarga el
    /// scheduler al cerrar la vuelta: la vuelta en curso se termina con el Cycle
    /// que estaba sonando, y el avance siguiente ya entra en el rango. Cortar un
    /// patrón por la mitad porque alguien movió un control táctil es exactamente
    /// lo que `product-guidelines.md` prohíbe.
    func testLoweringDoesNotTouchThePlaybackCursor() {
        let sounding = Track(cycle(pulses: 5)).withActiveCount(6).withCursor(4)

        XCTAssertEqual(sounding.withActiveCount(2).cursor, 4, "cortó la vuelta en curso")
    }

    // MARK: - El Cycle en edición

    /// El cursor de edición se acota al rango activo, no al de dieciséis: no se
    /// edita un Cycle que no se recorre.
    func testTheEditingCycleIsClampedToTheActiveRange() {
        let track = Track(cycle(pulses: 5)).withActiveCount(3)

        XCTAssertEqual(track.withEditing(-1).editing, 0)
        XCTAssertEqual(track.withEditing(9).editing, 2)
        XCTAssertEqual(track.withEditing(1).editing, 1)
    }

    /// Mover el Cycle en edición **no altera el cursor de reproducción** ni el
    /// material (FR7): es la separación que permite construir el B mientras
    /// suena el A.
    func testMovingTheEditingCycleChangesNothingElse() {
        let track = Track(cycle(pulses: 5)).withActiveCount(4).withCursor(2)
        let moved = track.withEditing(3)

        XCTAssertEqual(moved.cursor, 2)
        XCTAssertEqual(moved.activeCount, 4)
        for index in 0..<Track.cycleCount {
            XCTAssertEqual(moved.cycle(at: index), track.cycle(at: index))
        }
    }
}

/// Tests del recorrido: por qué Cycle pasa a ir el Track al cerrar la vuelta.
///
/// **Vive en `Engine` y no en el scheduler a propósito.** Es una regla del
/// modelo —qué sigue a qué— y no una regla de tiempo: quién decide *cuándo* se
/// avanza es el scheduler, y eso se testea en `MIDI` con un horizonte dado a
/// mano. Separarlas es lo que permite fijar aquí el recorrido con aritmética,
/// sin hilos y sin relojes.
final class TrackTraversalTests: XCTestCase {

    private var cycle: Cycle {
        Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!))
    }

    /// Con N activos, el cursor recorre 0…N−1 y vuelve a 0. Se comprueba sobre
    /// dos vueltas completas: una sola no distingue un recorrido de un contador
    /// que sigue subiendo.
    func testWithNActiveTheCursorWalksZeroToNMinusOneAndWrapsToZero() {
        for activeCount in 1...Track.cycleCount {
            var track = Track(cycle).withActiveCount(activeCount)
            var visited: [Int] = []

            for _ in 0..<(activeCount * 2) {
                visited.append(track.cursor)
                track = track.advanced()
            }

            let expected = Array(0..<activeCount) + Array(0..<activeCount)
            XCTAssertEqual(visited, expected, "con \(activeCount) activos")
        }
    }

    /// **FR10 — con un solo Cycle activo el cursor no se mueve nunca.** Es la
    /// condición de no regresión de la rebanada entera: un Track con un Cycle
    /// suena como el de la rebanada 1, sin avance y sin reinicio audible.
    func testWithASingleActiveCycleTheCursorNeverMoves() {
        var track = Track(cycle)

        for _ in 0..<1_000 {
            track = track.advanced()
            XCTAssertEqual(track.cursor, 0)
        }
    }

    /// **FR9 — con el cursor fuera del rango, el avance siguiente entra en 0.**
    /// Es el caso de bajar el número mientras suena: de 6 activos sonando el 5,
    /// se baja a 2. La vuelta en curso se termina con el Cycle que estaba
    /// sonando —el cursor no se toca al bajar— y el avance siguiente entra en el
    /// rango en vez de cortar el patrón por la mitad.
    func testACursorLeftOutOfRangeEntersAtZeroOnTheNextAdvance() {
        let stranded = Track(cycle).withActiveCount(6).withCursor(4).withActiveCount(2)

        XCTAssertEqual(stranded.cursor, 4, "bajar el número movió el cursor")
        XCTAssertEqual(stranded.advanced().cursor, 0)
    }

    /// Y desde ahí sigue recorriendo el rango nuevo, sin arrastrar nada del
    /// viejo.
    func testAfterEnteringTheRangeItKeepsWalkingTheNewOne() {
        var track = Track(cycle).withActiveCount(6).withCursor(4).withActiveCount(3).advanced()
        var visited: [Int] = []

        for _ in 0..<6 {
            visited.append(track.cursor)
            track = track.advanced()
        }

        XCTAssertEqual(visited, [0, 1, 2, 0, 1, 2])
    }

    /// Avanzar no toca nada más: ni el material, ni cuántos hay activos, ni el
    /// Cycle en edición. Lo mueve el hilo del scheduler, y ahí tocar de más es
    /// pisar lo que el hilo principal está editando.
    func testAdvancingTouchesNothingButThePlaybackCursor() {
        let track = Track(cycle).withActiveCount(4).withEditing(2)
        let advanced = track.advanced()

        XCTAssertEqual(advanced.activeCount, 4)
        XCTAssertEqual(advanced.editing, 2)
        for index in 0..<Track.cycleCount {
            XCTAssertEqual(advanced.cycle(at: index), track.cycle(at: index))
        }
    }

    /// La aritmética, aparte del Track: es lo que corre en el hilo del
    /// scheduler, y probarla sobre los números deja fijado que no hay
    /// asignaciones ni ramas escondidas.
    func testTheArithmeticOnItsOwn() {
        XCTAssertEqual(Track.cursorAfter(0, activeCount: 1), 0)
        XCTAssertEqual(Track.cursorAfter(0, activeCount: 4), 1)
        XCTAssertEqual(Track.cursorAfter(3, activeCount: 4), 0)
        XCTAssertEqual(Track.cursorAfter(9, activeCount: 4), 0, "cursor fuera de rango")
        XCTAssertEqual(Track.cursorAfter(15, activeCount: 16), 0)
    }
}

/// Tests de qué Cycle enseña la pantalla.
///
/// **La regla, desde el 2026-09-02: todo lo que se muestra es el Cycle en
/// edición.** El anillo, la lectura, el pool, la superficie de pads y el canal
/// son lo que los knobs están moviendo; lo único que enseña el que suena es el
/// relleno de la fila de Cycles.
///
/// **Se encontró en dispositivo y se lee como otra cosa.** Con el transporte
/// parado, mover el knob 10 y girar otro knob no cambiaba nada en pantalla: los
/// knobs editaban el Cycle 2 y la pantalla seguía enseñando el 1. El síntoma es
/// «el Track dejó de responder», que apunta a la entrada y no a la vista.
final class TheScreenShowsTheEditingCycleTests: XCTestCase {

    private func cycle(pulses: Int) -> Cycle {
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(pulses)!),
            pool: PitchPool().inserting(Pitch(48)!)
        )
    }

    /// Un Track editando el Cycle 2 mientras suena el 1.
    private func divergent() -> Pattern {
        let track =
            Track(cycle(pulses: 5))
            .withActiveCount(3)
            .replacing(cycle(pulses: 12), at: 1)
            .withEditing(1)
            .withCursor(0)
        return Pattern().replacing(track, at: 0)
    }

    /// Los dos accesos existen y **no devuelven lo mismo** cuando los cursores
    /// divergen: si devolvieran lo mismo, este test no probaría nada.
    func testTheTwoAccessorsDivergeWhenTheCursorsDo() {
        let pattern = divergent()

        XCTAssertEqual(pattern.cycle(at: 0)?.shape.pulses.count, 5, "el que suena")
        XCTAssertEqual(pattern.editingCycle(at: 0)?.shape.pulses.count, 12, "el que se edita")
    }

    /// El anillo dibuja el Cycle en edición. Sin esto, girar un knob no cambia
    /// nada en pantalla.
    func testTheRingDrawsTheEditingCycle() {
        let stack = RingStack(pattern: divergent())

        // Doce Pulses sobre dieciséis Steps, contra los cinco del Cycle que
        // suena: se cuentan en el anillo dibujado.
        XCTAssertEqual(stack.bands[0].ring.positions.filter(\.isPulse).count, 12)
    }

    /// Y el playhead cae sobre ese mismo anillo: sobre otro marcaría una
    /// posición de algo que no está en pantalla.
    func testThePlayheadFallsOnTheRingThatIsDrawn() {
        let heads = Playhead.forEachTrack(
            in: divergent(),
            tempo: Tempo(beatsPerMinute: 120)!,
            elapsedNanoseconds: 0
        )

        XCTAssertEqual(heads.count, Pattern.trackCount)
        XCTAssertEqual(heads[0].step, 0)
    }

    /// Con un solo Cycle activo los dos accesos coinciden, que es lo que hace
    /// que nada cambie para quien no use Cycles.
    func testWithASingleActiveCycleBothAccessorsAgree() {
        let pattern = Pattern().replacing(Track(cycle(pulses: 7)), at: 0)

        XCTAssertEqual(pattern.cycle(at: 0), pattern.editingCycle(at: 0))
    }
}
