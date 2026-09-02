import Engine

/// Publica la fase de los dieciséis schedulers hacia la interfaz sin locks.
///
/// Cada Track ocupa una palabra atómica: cuatro bits para cada uno de los tres
/// últimos cursores y los restantes para el Step que abrió la vuelta. El hilo
/// de audio solo escribe al cambiar de Cycle; leer tarde no puede frenarlo.
final class CyclePlaybackClock: @unchecked Sendable {

    private static let cursorMask: UInt64 = 0xF
    private let phases: UnsafeMutablePointer<AtomicCounter>

    init() {
        phases = .allocate(capacity: Pattern.trackCount)
        for index in 0..<Pattern.trackCount {
            phases.advanced(by: index).initialize(to: AtomicCounter())
        }
    }

    deinit {
        phases.deinitialize(count: Pattern.trackCount)
        phases.deallocate()
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
