/// Cuánto hay que mover el origen de la rejilla para volver a la fase del
/// maestro externo.
///
/// **Por qué existe.** El tempo estimado acierta de media, pero un error de
/// microsegundos por negra se acumula: al cabo de un minuto la app y el maestro
/// no caen en el mismo sitio. Comparar la fase una vez por negra y empujar el
/// origen devuelve la rejilla sin tocar el tempo.
///
/// **Por qué una vez por negra y no por tick.** El reloj entrante tiene su
/// propio jitter, y corregir a 24 ppqn lo traslada entero a la salida — que es
/// lo contrario de lo que hace bueno el timing del proyecto. La enmienda del
/// 2026-09-03 de `tech-stack.md` lo deja escrito.
///
/// **Es una función, no un objeto.** No guarda estado: recibe el origen vigente,
/// la duración de la negra y el instante del tick del maestro, y devuelve
/// cuántos nanosegundos hay que **sumar** al origen. Quien la llame decide si
/// aplicarla.
public enum PhaseCorrection {

    /// Nanosegundos a sumar al origen de la rejilla para alinearla con el tick.
    ///
    /// El resultado es la distancia con signo desde el límite de rejilla **más
    /// cercano** hasta el tick del maestro:
    ///
    /// - **Positivo** cuando la rejilla va adelantada —su límite cayó antes que
    ///   el tick—, así que el origen se retrasa.
    /// - **Negativo** cuando va atrasada, así que el origen se adelanta.
    ///
    /// Se acota a `limitNanoseconds` en los dos sentidos: un tick absurdamente
    /// desviado no puede producir un salto arbitrario, y lo que sobra se corrige
    /// en las negras siguientes. Un límite de cero desactiva la corrección sin
    /// obligar a quien llama a poner una rama.
    ///
    /// Devuelve cero si la negra no tiene duración positiva: sin ella no hay
    /// fase que medir.
    ///
    /// Realtime: llamado desde el hilo de recepción de CoreMIDI.
    /// Sin asignaciones, sin locks, sin await.
    public static func nanoseconds(
        gridOriginNanoseconds origin: Int64,
        quarterNoteNanoseconds quarterNote: Double,
        masterTickNanoseconds tick: Int64,
        limitNanoseconds limit: Int64
    ) -> Int64 {
        guard quarterNote > 0 else { return 0 }

        // Fase del tick dentro de la negra, siempre en [0, negra): el resto de
        // Swift conserva el signo del dividendo, y el origen puede caer después
        // del tick.
        let elapsed = Double(tick - origin)
        var phase = elapsed.truncatingRemainder(dividingBy: quarterNote)
        if phase < 0 { phase += quarterNote }

        // Contra el límite más cercano: pasada la mitad de la negra, el pulso
        // que viene está más cerca que el que pasó.
        let error = phase > quarterNote / 2 ? phase - quarterNote : phase
        let correction = Int64(error.rounded())

        return min(max(correction, -limit), limit)
    }
}
