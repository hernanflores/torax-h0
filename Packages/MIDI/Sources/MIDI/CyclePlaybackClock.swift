import Engine

/// Publica la fase de los dieciséis schedulers hacia la interfaz sin locks.
///
/// Cada Track ocupa una palabra atómica: cuatro bits para cada uno de los tres
/// últimos cursores y los restantes para el Step que abrió la vuelta. El hilo
/// de audio solo escribe al cambiar de Cycle; leer tarde no puede frenarlo.
///
/// **Publica también la rejilla de cada Track**, desde la Fase 5 de
/// `division-hot-grid_20260911`. La rejilla se reancla mientras suena, así que
/// el anillo ya no puede suponer que se mide desde el origen de Play: tiene que
/// medir con el ancla que usa el scheduler. Lo que cruza son enteros —índice de
/// Step, instante y Division, de la rejilla vigente y de la anterior— y la
/// interfaz reconstruye la `MusicalTimeline` con su propio tempo (NFR5b).
///
/// **Esas son seis palabras por Track, y no caben en un atómico.** Se protegen
/// con un seqlock: el escritor sube una generación a impar, escribe y la vuelve
/// a par; el lector descarta lo que leyó si la generación cambió por medio. El
/// escritor es el hilo del scheduler y nunca espera. El que reintenta es el
/// lector, que es la interfaz. Hay un solo escritor, porque los dieciséis
/// `TrackScheduler` corren en ese hilo, así que basta una generación para
/// todos.
final class CyclePlaybackClock: @unchecked Sendable {

    private static let cursorMask: UInt64 = 0xF
    private let phases: UnsafeMutablePointer<AtomicCounter>

    /// Índice de Step, instante y Division empaquetada: una rejilla.
    private static let wordsPerGrid = 3
    /// La vigente y la anterior.
    private static let wordsPerTrack = 2 * wordsPerGrid
    private static let gridWordCount = Pattern.trackCount * wordsPerTrack

    /// Cuántas veces reintenta la interfaz antes de rendirse y dibujar sin
    /// rejilla publicada, como antes de este track. Publicar es raro —un
    /// reanclaje—, así que en la práctica nunca pasa de la segunda; la cota
    /// existe para que un escritor desbocado no pueda colgar el redibujado.
    private static let readAttempts = 8

    private let gridWords: UnsafeMutablePointer<AtomicCounter>
    private let gridGeneration = AtomicCounter()

    init() {
        phases = .allocate(capacity: Pattern.trackCount)
        for index in 0..<Pattern.trackCount {
            phases.advanced(by: index).initialize(to: AtomicCounter())
        }
        gridWords = .allocate(capacity: Self.gridWordCount)
        for index in 0..<Self.gridWordCount {
            gridWords.advanced(by: index).initialize(to: AtomicCounter())
        }
    }

    deinit {
        phases.deinitialize(count: Pattern.trackCount)
        phases.deallocate()
        gridWords.deinitialize(count: Self.gridWordCount)
        gridWords.deallocate()
    }

    /// Publica la rejilla vigente de un Track y la que había antes.
    ///
    /// **La generación sube con `increment`, no con una escritura.** Es una
    /// lectura-modificación-escritura con orden adquisición-liberación, y eso
    /// impide que las palabras de la rejilla se hagan visibles antes que la
    /// generación impar. Con una escritura de liberación sí podrían, y el
    /// lector aceptaría una rejilla a medias.
    ///
    /// Realtime: llamado solo al reanclar y al arrancar.
    /// Sin asignaciones, sin locks, sin await.
    func publishGrid(track: Int, current: MusicalTimeline, previous: MusicalTimeline) {
        guard (0..<Pattern.trackCount).contains(track) else { return }
        let base = track * Self.wordsPerTrack
        gridGeneration.increment()
        store(current, at: base)
        store(previous, at: base + Self.wordsPerGrid)
        gridGeneration.increment()
    }

    /// Realtime: llamado desde `publishGrid`.
    /// Sin asignaciones, sin locks, sin await.
    private func store(_ timeline: MusicalTimeline, at index: Int) {
        gridWords[index].value = UInt64(bitPattern: Int64(timeline.anchorStep))
        gridWords[index + 1].value = UInt64(bitPattern: timeline.anchorNanoseconds)
        // Numerador y denominador en 32 bits cada uno: el knob recorre 1/1 a
        // 1/32 y el tipo admite cualquier fracción positiva, pero ninguna que
        // se acerque a cuatro mil millones.
        gridWords[index + 2].value =
            UInt64(UInt32(truncatingIfNeeded: timeline.division.numerator)) << 32
            | UInt64(UInt32(truncatingIfNeeded: timeline.division.denominator))
    }

    /// Las rejillas de los dieciséis, leídas de una misma publicación.
    ///
    /// `nil` para un Track del que nadie publicó nada, y para los dieciséis si
    /// no se consiguió una lectura entera en `readAttempts` intentos: la
    /// interfaz dibuja entonces como si no hubiera anclas, que es lo de antes de
    /// este track, en vez de dibujar una rejilla inventada.
    ///
    /// Lo llama la interfaz al redibujar. No es código de tiempo real.
    func grids(tempo: Tempo) -> [PlaybackGrid?] {
        for _ in 0..<Self.readAttempts {
            let before = gridGeneration.value
            guard before & 1 == 0 else { continue }
            let grids = (0..<Pattern.trackCount).map { grid(track: $0, tempo: tempo) }
            if gridGeneration.value == before { return grids }
        }
        return Array(repeating: nil, count: Pattern.trackCount)
    }

    private func grid(track: Int, tempo: Tempo) -> PlaybackGrid? {
        let base = track * Self.wordsPerTrack
        guard let current = timeline(at: base, tempo: tempo),
            let previous = timeline(at: base + Self.wordsPerGrid, tempo: tempo)
        else { return nil }
        return PlaybackGrid(current: current, previous: previous)
    }

    /// `nil` con las palabras a cero, que es un Track sin publicar: una
    /// Division de 0/0 no existe.
    private func timeline(at index: Int, tempo: Tempo) -> MusicalTimeline? {
        let packed = gridWords[index + 2].value
        guard
            let division = Division(
                numerator: Int(packed >> 32), denominator: Int(packed & 0xFFFF_FFFF))
        else { return nil }
        return MusicalTimeline(
            tempo: tempo,
            division: division,
            anchorStep: Int(Int64(bitPattern: gridWords[index].value)),
            anchorNanoseconds: Int64(bitPattern: gridWords[index + 1].value)
        )
    }

    /// Realtime: llamado solo al cruzar un límite de vuelta.
    /// Sin asignaciones, sin locks, sin await.
    func publish(
        track: Int,
        cycle: Int,
        previousCycle: Int,
        earlierCycle: Int,
        turnStartStep: Int
    ) {
        guard (0..<Pattern.trackCount).contains(track) else { return }
        let packed =
            UInt64(max(0, turnStartStep)) << 12
            | UInt64(earlierCycle & 0xF) << 8
            | UInt64(previousCycle & 0xF) << 4
            | UInt64(cycle & 0xF)
        phases[track].value = packed
    }

    func positions(in pattern: Pattern, tempo: Tempo, elapsedNanoseconds: Int64)
        -> [CyclePosition]
    {
        (0..<Pattern.trackCount).map { index in
            let packed = phases[index].value
            let phase = CyclePosition.Phase(
                cycle: Int(packed & Self.cursorMask),
                previousCycle: Int((packed >> 4) & Self.cursorMask),
                earlierCycle: Int((packed >> 8) & Self.cursorMask),
                turnStartStep: Int(packed >> 12)
            )
            return CyclePosition(
                elapsedNanoseconds: elapsedNanoseconds,
                track: pattern.track(at: index)!,
                tempo: tempo,
                phase: phase
            )
        }
    }
}
