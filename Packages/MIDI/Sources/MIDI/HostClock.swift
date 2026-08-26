import Darwin

/// Convierte entre nanosegundos y el tiempo de host que usa CoreMIDI.
///
/// **Por qué existe este tipo.** CoreMIDI sella los eventos con tiempo de host
/// (`mach_absolute_time`), cuya unidad no es el nanosegundo en todas las
/// máquinas: en Apple Silicon la relación es 1:1, pero en Intel no lo es. Dar
/// por hecha esa equivalencia produce un tempo correcto en unos dispositivos y
/// equivocado en otros — un fallo que no aparece en la máquina donde se
/// desarrolla. La conversión se hace aquí, explícita y con tests.
public enum HostClock {

    /// Relación ticks↔nanosegundos de esta máquina. Se consulta una vez: el
    /// valor es constante durante la vida del proceso y el hilo del scheduler
    /// no puede permitirse una llamada al kernel por evento.
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Instante actual, en ticks de host.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public static func now() -> UInt64 {
        mach_absolute_time()
    }

    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public static func nanoseconds(fromHostTicks ticks: UInt64) -> UInt64 {
        ticks &* UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public static func hostTicks(fromNanoseconds nanoseconds: UInt64) -> UInt64 {
        nanoseconds &* UInt64(timebase.denom) / UInt64(timebase.numer)
    }
}
