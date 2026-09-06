/// Qué había debajo de los doce Tracks durante un Ctrl All, y cuánto se ha
/// desplazado cada parámetro.
///
/// **Es la memoria del gesto, no el gesto.** Mientras se mantiene [step 14] los
/// giros de knob desplazan un parámetro en los doce Tracks sin escribir en el
/// Pattern; este valor es lo único que permite deshacerlo al soltar. Quién
/// mantiene el botón y cuándo lo suelta es de `ControlInput`; aquí solo hay
/// valor puro, que es donde `workflow.md` pide que viva la regla.
///
/// > **Desplaza, no iguala — y ahí está toda la diferencia con
/// > [`ParameterOverlay`].** Temp existe para que un parámetro suene **igual** en
/// > todos los Cycles del Track seleccionado, así que escribe un valor absoluto.
/// > Ctrl All existe para lo contrario: mover el Pattern entero **conservando**
/// > lo que lo hace un Pattern y no doce copias. Un Track lento sigue siendo el
/// > lento; el que tenía menos Pulses sigue teniendo menos. Por eso lo que se
/// > acumula es un delta y no un destino.
///
/// **Guarda base y desplazamiento por separado, y no el valor superpuesto.** El
/// valor de cada Cycle se recalcula siempre como base + offset. Es lo único que
/// hace exacta la ida y vuelta cuando un Track topa contra su extremo: guardando
/// el valor ya acotado, desandar el giro dejaría al topado clavado en el tope
/// mientras los demás vuelven, y el balance del Pattern quedaría destruido por
/// un gesto que promete no escribir nada.
///
/// **El snapshot va acotado** (NFR3): solo los parámetros que la mano toca, y
/// solo por los Cycles activos de cada Track. No es una copia del Pattern
/// (~37 KB), que sería lo fácil y lo que además rebobinaría los cursores.
///
/// **No cruza al hilo del scheduler** (NFR2). Vive en el hilo de control, que es
/// por lo que puede permitirse un `Dictionary`: lo que cruza sigue siendo un
/// `Pattern` normal por el `PatternHandoff` de siempre.
public struct CtrlAllOffset: Equatable, Sendable {

    /// Por parámetro tocado, el valor base de cada Cycle activo de cada Track.
    ///
    /// La clave interior es el par `(Track, Cycle)` porque lo que se pregunta es
    /// «¿qué tenía este parámetro aquí?», y no al revés.
    private var bases: [TrackParameter: [Position: Int]]

    /// Por parámetro tocado, cuánto se lleva desplazado.
    private var amounts: [TrackParameter: Int]

    /// Dónde vive un Cycle: en qué Track y en qué hueco.
    ///
    /// **Un par y no dos diccionarios anidados.** Lo que se guarda es plano
    /// —doce Tracks por sus Cycles activos— y anidarlo obligaría a distinguir
    /// «Track sin capturar» de «Track capturado sin Cycles», que no son estados
    /// distintos para nadie.
    private struct Position: Hashable, Sendable {
        let track: Int
        let cycle: Int
    }

    /// El estado de reposo: nada desplazado.
    public init() {
        bases = [:]
        amounts = [:]
    }

    /// Si no hay nada desplazado.
    ///
    /// Es el estado mientras nadie mantiene el step 14, y también el de un hold
    /// en el que no se llegó a girar ningún knob.
    public var isEmpty: Bool { bases.isEmpty }

    /// Qué parámetros se han tocado, en el orden de `TrackParameter`.
    ///
    /// El orden va declarado y no heredado del recorrido de un `Dictionary`, por
    /// la misma razón que en `ParameterOverlay`: un orden que cambia entre
    /// ejecuciones convierte un test en un lanzamiento de moneda.
    public var parameters: [TrackParameter] {
        TrackParameter.allCases.filter { bases[$0] != nil }
    }

    /// El valor base de ese parámetro en ese Cycle de ese Track, o `nil` si no
    /// se guardó.
    ///
    /// `nil` no es un error: es lo que devuelve un parámetro que nadie giró y lo
    /// que devuelve un Cycle que no estaba activo cuando empezó el hold.
    public func base(of parameter: TrackParameter, track: Int, cycle: Int) -> Int? {
        bases[parameter]?[Position(track: track, cycle: cycle)]
    }

    /// Cuánto se lleva desplazado ese parámetro.
    ///
    /// **Cero para un parámetro sin tocar, no `nil`.** Preguntar por él es lo
    /// normal —quien aplica el desplazamiento no sabe de antemano cuáles se han
    /// girado— y cero es la respuesta correcta: no moverse.
    public func amount(of parameter: TrackParameter) -> Int {
        amounts[parameter] ?? 0
    }

    /// El mismo offset con la base de ese parámetro guardada, si no lo estaba ya.
    ///
    /// **Guardar dos veces el mismo parámetro no re-guarda la base**, y ese es el
    /// caso normal y no el raro: girar un knob durante el hold produce un mensaje
    /// tras otro, y el segundo llega cuando el Pattern ya lleva el
    /// desplazamiento puesto. Si cada mensaje reescribiera la base, se guardaría
    /// el valor desplazado y soltar dejaría el gesto escrito para siempre — que
    /// es exactamente lo que este tipo existe para impedir.
    ///
    /// Solo se recorren los Cycles **activos** de cada Track: los demás no se
    /// tocan, así que no hay nada suyo que devolver.
    ///
    /// **Los Tracks muteados se capturan como cualquier otro** (FR3). Mute es
    /// mezcla y no material: la rejilla del muteado sigue avanzando, así que
    /// dejarlo fuera lo devolvería desalineado al desmutearlo. Aquí ni siquiera
    /// se puede consultar, y es lo correcto — la máscara vive en `MIDI`.
    public func capturing(_ parameter: TrackParameter, from pattern: Pattern) -> CtrlAllOffset {
        guard bases[parameter] == nil else { return self }

        var captured: [Position: Int] = [:]
        for trackIndex in 0..<Pattern.trackCount {
            guard let track = pattern.track(at: trackIndex) else { continue }
            for cycleIndex in 0..<track.activeCount {
                guard let cycle = track.cycle(at: cycleIndex) else { continue }
                captured[Position(track: trackIndex, cycle: cycleIndex)] = cycle.value(
                    of: parameter)
            }
        }

        var updated = self
        updated.bases[parameter] = captured
        return updated
    }

    /// El mismo offset con ese parámetro desplazado `delta` posiciones más.
    ///
    /// **Acumula sobre el desplazamiento, no sobre el valor.** Girar dos veces
    /// suma, y girar de vuelta desanda hasta cero exacto: es lo que permite
    /// devolver el Pattern a su sitio aunque por el camino algún Track haya
    /// topado contra su extremo.
    public func advancing(_ parameter: TrackParameter, by delta: Int) -> CtrlAllOffset {
        var updated = self
        updated.amounts[parameter] = amount(of: parameter) + delta
        return updated
    }

    /// El Pattern con cada parámetro tocado devuelto a **su** valor en **cada**
    /// Cycle de **cada** Track.
    ///
    /// **Devuelve los parámetros tocados y nada más** (FR8). No es un snapshot
    /// literal del Pattern a propósito: los cursores de reproducción avanzaron
    /// durante el hold y no pueden retroceder, así que restaurar el Pattern
    /// entero rebobinaría la música. Lo que queda intacto por construcción es
    /// todo lo que este valor no guarda — los dos cursores, `activeCount`, el
    /// pool, el marco tonal, el canal y `padOctaveShift`.
    ///
    /// Desde el reposo devuelve el Pattern tal cual: soltar el step 14 sin haber
    /// girado nada se queda en nada.
    public func restored(into pattern: Pattern) -> Pattern {
        var restored = pattern
        for (parameter, byPosition) in bases {
            for (position, value) in byPosition {
                guard let track = restored.track(at: position.track),
                    let cycle = track.cycle(at: position.cycle)
                else { continue }
                restored = restored.replacing(
                    track.replacing(cycle.setting(parameter, to: value), at: position.cycle),
                    at: position.track)
            }
        }
        return restored
    }
}
