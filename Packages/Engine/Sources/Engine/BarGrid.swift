/// Dónde cae el próximo límite de compás.
///
/// **Cuatro negras es una decisión, no una lectura del modelo.** La app no tiene
/// concepto de compás ni de métrica: `MusicalTimeline` cuenta negras y los Steps
/// salen de Division. Esto se añade porque el cambio de Pattern tiene que caer
/// en algún sitio común, y cuatro negras es lo que asume cualquier secuenciador
/// de hardware y lo que hace que un cambio de sección caiga donde el oído lo
/// espera.
///
/// **No es el límite de vuelta de ningún Track.** Los doce tienen anillos de
/// longitudes distintas —Steps × Division— y esperar a que cierren todos no
/// converge: dos Tracks primos entre sí coinciden una vez cada muchos compases.
/// El compás es la única rejilla común, y por eso el cambio de Pattern entra en
/// los doce a la vez.
///
/// El origen es el mismo que el de `MusicalTimeline`: quien programa lo fija.
/// Este tipo no conoce el tiempo de host, y por eso vive en `Engine`.
public struct BarGrid: Equatable, Sendable {

    /// Cuántas negras tiene un compás. **Es la decisión**, y está sola en una
    /// constante para que se vea que lo es.
    public static let beatsPerBar = 4

    public let tempo: Tempo

    public init(tempo: Tempo) {
        self.tempo = tempo
    }

    /// Cuánto dura un compás, en nanosegundos. A 120 BPM son 2 s.
    public var durationNanoseconds: Int64 {
        let nanosecondsPerBeat = 60.0 / tempo.beatsPerMinute * 1_000_000_000.0
        return Int64((nanosecondsPerBeat * Double(Self.beatsPerBar)).rounded())
    }

    /// El próximo límite estrictamente **después** de ese instante.
    ///
    /// **Estar exactamente encima devuelve el siguiente, no ése**, y es la
    /// decisión que hay que mirar dos veces. La razón es de tiempo real: el
    /// scheduler pregunta con la ventana de look-ahead ya sumada, así que un
    /// límite que cae justo en el instante consultado **ya está comprometido**
    /// —sus eventos se pidieron hace 20 ms—. Devolverlo produciría un cambio que
    /// llega tarde a su propio compás.
    ///
    /// Antes del origen devuelve el origen: es lo que produce un Delay negativo,
    /// y no es un error.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func nextBoundary(after nanoseconds: Int64) -> Int64 {
        guard nanoseconds >= 0 else { return 0 }
        let duration = durationNanoseconds
        return (nanoseconds / duration + 1) * duration
    }

    /// Cuánto falta para el próximo límite. Es lo que la cuenta atrás de la
    /// pantalla enseña mientras un Pattern espera (FR25).
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func remainingNanoseconds(at nanoseconds: Int64) -> Int64 {
        nextBoundary(after: nanoseconds) - Swift.max(nanoseconds, 0)
    }
}
