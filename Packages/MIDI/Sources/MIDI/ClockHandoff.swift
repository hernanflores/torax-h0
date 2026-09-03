/// Lo que el scheduler necesita saber del reloj externo.
///
/// Los dos valores solo valen juntos, y por eso viajan juntos: ver el periodo de
/// una negra con la corrección de la siguiente es una rejilla que salta sin que
/// nada lo explique.
public struct ClockReading: Equatable, Sendable {

    /// Duración de la negra según el maestro, o `0` si todavía no hay tempo.
    public let quarterNoteNanoseconds: UInt32

    /// Suma de todas las correcciones de fase publicadas desde el arranque.
    ///
    /// **Es acumulada y no la última**, para que el scheduler no dependa de leer
    /// exactamente una vez cada negra: guarda cuánto llevaba aplicado y aplica
    /// la diferencia. Si lee dos veces la misma, la diferencia es cero; si se
    /// salta una, la recupera entera.
    public let accumulatedCorrectionNanoseconds: Int32

    /// Si ya se cerró una negra con un tempo válido.
    ///
    /// Es un estado, no un cero disfrazado: sin tempo del maestro el transporte
    /// no puede sellar nada, y quien lee tiene que poder distinguirlo.
    public var isEstablished: Bool { quarterNoteNanoseconds > 0 }
}

/// Entrega el reloj externo al hilo del scheduler, sin lock.
///
/// **Es el tercer camino sin lock del proyecto**, y el único que publica dos
/// valores. `PatternHandoff` lleva material del hilo de control al del scheduler
/// con un anillo de ranuras, porque un `Pattern` son 37 KB; `PlayheadClock` lleva
/// un entero del scheduler a la interfaz. Aquí van dos, del hilo de recepción de
/// CoreMIDI al del scheduler.
///
/// **Los dos caben en una palabra, así que no hace falta protocolo.** La negra
/// más larga del rango —20 BPM— son 3.000 millones de nanosegundos, que entran en
/// 32 bits; la corrección acumulada va en los otros 32 con signo. Un `store` y un
/// `load` atómicos de 64 bits los entregan coherentes, que es exactamente el
/// mismo criterio con el que `MuteMask` mete doce mutes y doce solos en un
/// `UInt64`: dos atómicos permitirían leer la mitad de cada publicación.
///
/// **Un solo escritor.** Publica el hilo de recepción de CoreMIDI y nadie más,
/// así que acumular la corrección es leer y escribir sin carrera.
public final class ClockHandoff: @unchecked Sendable {

    /// Negra en los 32 bits altos, corrección acumulada en los bajos.
    private let word = AtomicCounter(0)

    public init() {}

    /// Publica lo que se sabe del maestro tras cerrar una negra.
    ///
    /// Realtime: llamado desde el hilo de recepción de CoreMIDI.
    /// Sin asignaciones, sin locks, sin await.
    func publish(quarterNoteNanoseconds: UInt32, accumulatedCorrectionNanoseconds: Int32) {
        word.value =
            UInt64(quarterNoteNanoseconds) << 32
            | UInt64(UInt32(bitPattern: accumulatedCorrectionNanoseconds))
    }

    /// Olvida el maestro. Lo llama el arranque del transporte: el reloj anterior
    /// no dice nada del siguiente.
    ///
    /// Realtime: llamado desde el hilo del scheduler al arrancar.
    /// Sin asignaciones, sin locks, sin await.
    func clear() {
        word.value = 0
    }

    /// El periodo y la corrección, de la misma publicación.
    ///
    /// Realtime: llamado desde el hilo del scheduler, una vez por ventana.
    /// Sin asignaciones, sin locks, sin await.
    public var reading: ClockReading {
        let value = word.value
        return ClockReading(
            quarterNoteNanoseconds: UInt32(truncatingIfNeeded: value >> 32),
            accumulatedCorrectionNanoseconds: Int32(bitPattern: UInt32(truncatingIfNeeded: value)))
    }
}
