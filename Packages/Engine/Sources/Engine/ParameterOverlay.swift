/// Qué parámetros se superpusieron durante un Temp, y qué había debajo.
///
/// **Es la memoria del gesto, no el gesto.** Mientras se mantiene [step 13] los
/// giros de knob cambian lo que suena sin escribir en el Pattern; este valor es
/// lo único que permite deshacerlo al soltar. Quién mantiene el botón y cuándo
/// lo suelta es de `ControlInput`; aquí solo hay valor puro, que es donde
/// `workflow.md` pide que viva la regla.
///
/// > **Por qué la base se guarda por Cycle y no un valor único.** El overlay
/// > **iguala**: el parámetro girado toma el mismo valor absoluto en todos los
/// > Cycles activos, para que el fill se oiga aunque el cursor cruce de Cycle a
/// > media vuelta. Eso significa que lo que había debajo era **distinto en cada
/// > Cycle** —esa es toda la gracia de tener dieciséis—, así que un solo valor
/// > no podría devolverlo: al soltar, el Cycle 2 volvería al valor del Cycle 1 y
/// > el desarrollo A/B/C quedaría aplanado de forma permanente. El overlay
/// > aplana mientras dura y no después (FR4).
///
/// **El snapshot va acotado** (NFR3): solo los parámetros que la mano toca, y
/// solo por los Cycles activos. No es una copia del Track (~3 KB) ni del Pattern
/// (~37 KB), que sería lo fácil y lo que además rebobinaría los cursores.
///
/// **No cruza al hilo del scheduler** (NFR2). Vive en el hilo de control, que es
/// por lo que puede permitirse un `Dictionary`: lo que cruza sigue siendo un
/// `Pattern` normal por el `PatternHandoff` de siempre.
///
/// > **Un fill de Division suena desde `division-hot-grid_20260911`, y sin
/// > tocar este tipo.** Antes, superponer Division cambiaba la duración de la
/// > nota y no la velocidad de la línea, porque la rejilla se congelaba en Play.
/// > Ahora el scheduler reancla con cada `Pattern` que recibe, así que la
/// > pulsación y la soltada son dos reanclajes normales. Soltar no rebobina: la
/// > rejilla vuelve anclada al instante de la soltada. Con `CtrlAllOffset`
/// > pasa lo mismo, con doce reanclajes en la misma ventana. Lo fijan
/// > `DivisionTempOverlayTests` y `DivisionCtrlAllTests`, en `MIDI`.
public struct ParameterOverlay: Equatable, Sendable {

    /// Por parámetro tocado, el valor base de cada Cycle activo.
    ///
    /// El índice del Cycle es la clave interior porque lo que se pregunta es
    /// «¿qué tenía este parámetro en este Cycle?», y no al revés.
    private var bases: [TrackParameter: [Int: Int]]

    /// El estado de reposo: nada superpuesto.
    public init() {
        bases = [:]
    }

    /// Si no hay nada superpuesto.
    ///
    /// Es el estado mientras nadie mantiene el step 13, y también el de un hold
    /// en el que no se llegó a girar ningún knob.
    public var isEmpty: Bool { bases.isEmpty }

    /// Qué parámetros se han tocado, en el orden de `TrackParameter`.
    ///
    /// El orden va declarado y no heredado del recorrido de un `Dictionary`, por
    /// la misma razón que en `ParameterChange`: un orden que cambia entre
    /// ejecuciones convierte un test en un lanzamiento de moneda.
    public var parameters: [TrackParameter] {
        TrackParameter.allCases.filter { bases[$0] != nil }
    }

    /// El valor base de ese parámetro en ese Cycle, o `nil` si no se guardó.
    ///
    /// `nil` no es un error: es lo que devuelve un parámetro que nadie giró y lo
    /// que devuelve un Cycle que no estaba activo cuando empezó el hold.
    public func base(of parameter: TrackParameter, inCycle index: Int) -> Int? {
        bases[parameter]?[index]
    }

    /// El mismo overlay con la base de ese parámetro guardada, si no lo estaba
    /// ya.
    ///
    /// **Guardar dos veces el mismo parámetro no re-guarda la base**, y ese es
    /// el caso normal y no el raro: girar un knob durante el hold produce un
    /// mensaje tras otro, y el segundo llega cuando el Track ya lleva el overlay
    /// puesto. Si cada mensaje reescribiera la base, se guardaría el valor
    /// superpuesto y soltar dejaría el fill puesto para siempre — que es
    /// exactamente lo que este tipo existe para impedir.
    ///
    /// Solo se recorren los Cycles **activos**: los demás no se tocan, así que no
    /// hay nada suyo que devolver.
    public func capturing(_ parameter: TrackParameter, from track: Track) -> ParameterOverlay {
        guard bases[parameter] == nil else { return self }

        var captured: [Int: Int] = [:]
        for index in 0..<track.activeCount {
            guard let cycle = track.cycle(at: index) else { continue }
            captured[index] = cycle.value(of: parameter)
        }

        var updated = self
        updated.bases[parameter] = captured
        return updated
    }

    /// El Track con ese parámetro superpuesto, guardando la base si aún no lo
    /// estaba.
    ///
    /// **Iguala en vez de desplazar** (FR2). El delta se resuelve contra el
    /// **Cycle en edición** —donde está la mano— y el valor absoluto resultante
    /// se escribe igual en todos los Cycles activos. Aplicar el delta a cada uno
    /// por separado sería lo natural y estaría mal: con Pulses 5, 7 y 9 y un
    /// clic, seguirían siendo tres valores distintos y el fill sonaría distinto
    /// según por dónde fuera el cursor, que es justo lo que Temp evita.
    ///
    /// **Girar dos veces acumula sobre el valor superpuesto**, no sobre el base,
    /// porque el Track que entra ya lo lleva puesto. Si acumulara sobre el base,
    /// seguir girando no movería nada después del primer clic.
    ///
    /// Los Cycles inactivos no se tocan: el overlay alcanza a lo que se recorre.
    ///
    /// > **Igualar sigue al Cycle en edición: si él no se mueve, no se mueve
    /// > nadie** (FR9). Un giro nulo o contra un extremo devuelve el Track tal
    /// > cual y ni siquiera guarda la base, para que quien publica lo detecte
    /// > comparando, como hoy. La alternativa —igualar de todas formas— aplanaría
    /// > los otros Cycles sin que nadie hubiera girado nada, que es un cambio que
    /// > el usuario no pidió y no vería venir. Y no le quita nada al gesto: la
    /// > igualación ya ocurrió en el giro que sí movió el Cycle en edición.
    ///
    /// Es `mutating` porque el primer giro de cada parámetro guarda su base, y
    /// eso es estado del hold. Lo que devuelve es el Track, no el overlay: son
    /// dos cosas distintas y quien las junta es `ControlInput`.
    public mutating func apply(_ delta: Int, to parameter: TrackParameter, in track: Track)
        -> Track
    {
        let target = track.editingCycle.applying(delta, to: parameter).value(of: parameter)
        guard target != track.editingCycle.value(of: parameter) else { return track }

        self = capturing(parameter, from: track)

        var overlaid = track
        for index in 0..<track.activeCount {
            guard let cycle = overlaid.cycle(at: index) else { continue }
            overlaid = overlaid.replacing(cycle.setting(parameter, to: target), at: index)
        }
        return overlaid
    }

    /// El Track con cada parámetro tocado devuelto a **su** valor en **cada**
    /// Cycle.
    ///
    /// **Devuelve los parámetros tocados y nada más** (FR4). No es un snapshot
    /// literal del Track a propósito: el cursor de reproducción avanzó durante el
    /// hold y no puede retroceder, así que restaurar el Track entero rebobinaría
    /// la música. Lo que queda intacto por construcción es todo lo que este valor
    /// no guarda — los dos cursores, `activeCount`, el pool, el marco tonal, el
    /// canal y `padOctaveShift`.
    ///
    /// Desde el reposo devuelve el Track tal cual: soltar el step 13 sin haber
    /// girado nada se queda en nada.
    public func restored(into track: Track) -> Track {
        var restored = track
        for (parameter, byCycle) in bases {
            for (index, value) in byCycle {
                guard let cycle = restored.cycle(at: index) else { continue }
                restored = restored.replacing(cycle.restoring(parameter, to: value), at: index)
            }
        }
        return restored
    }
}

extension Cycle {

    /// El valor de ese parámetro, en la unidad en la que lo mueve el knob.
    ///
    /// **Es la posición del knob y no siempre el número que se enseña.** Para
    /// ocho de los nueve coinciden, pero Division es una fracción y su knob
    /// recorre una lista: su valor aquí es el índice en `Division.ordered`, que
    /// es lo único con lo que un delta tiene sentido. Devolver el denominador
    /// haría que superponer Division saltara de 1/16 a 1/1 con un solo clic.
    ///
    /// Una Division fuera del recorrido devuelve 0 porque no tiene posición. No
    /// es alcanzable —el valor por defecto está en la lista y `advanced(by:)` no
    /// sale de ella— y no puede corromper nada: `setting(_:to:)` calcula un delta
    /// y `Division.advanced(by:)` devuelve la misma Division si no la reconoce.
    public func value(of parameter: TrackParameter) -> Int {
        switch parameter {
        case .steps: shape.steps.count
        case .pulses: shape.pulses.count
        case .rotate: shape.rotate.amount
        case .division: Division.ordered.firstIndex(of: shape.division) ?? 0
        case .repeats: noteRepeater.repeats.count
        // Como Division, y por lo mismo: el knob recorre una lista, así que su
        // posición es el índice y no el denominador.
        case .repeatTime: RepeatTime.ordered.firstIndex(of: noteRepeater.time) ?? 0
        case .ramp: noteRepeater.ramp.percent
        case .pace: noteRepeater.pace.percent
        case .velocity: groove.velocity.value
        case .sustain: groove.sustain.percent
        case .probability: groove.probability.percent
        case .timing: groove.timing.percent
        case .delay: groove.delay.percent
        case .pitch: pitchOffset.degrees
        // Sin posición: Harmony es estado. Temp y Ctrl All lo tratan aparte.
        case .harmony: 0
        }
    }

    /// El mismo Cycle con ese parámetro puesto en ese valor absoluto.
    ///
    /// **Se apoya en `applying(_:to:)` en vez de repetir la aritmética**: cada
    /// parámetro sabe frenarse en su extremo —o envolver, en el caso de Rotate—
    /// y duplicar esas reglas aquí sería tener dos sitios donde equivocarse. Un
    /// valor fuera de rango se frena exactamente donde lo haría el knob.
    ///
    /// Es lo que hace falta para **igualar**: Temp calcula un valor absoluto
    /// desde el Cycle en edición y lo escribe igual en todos los activos, que con
    /// deltas no se podría, porque cada Cycle parte de un valor distinto.
    public func setting(_ parameter: TrackParameter, to value: Int) -> Cycle {
        applying(value - self.value(of: parameter), to: parameter)
    }
}

extension Cycle {

    /// El mismo Cycle con ese parámetro **devuelto** al valor que tenía antes de
    /// un Temp o un Ctrl All.
    ///
    /// **Para casi todos es `setting(_:to:)`**: el valor capturado cabía cuando
    /// se capturó, y el freno de cada parámetro no depende de nada que el hold
    /// pueda mover.
    ///
    /// **Pitch es la excepción, y se devuelve literal** (`pitch-harmony_20260912`).
    /// Su freno depende del pool y de Harmony, y Harmony sí puede moverse durante
    /// el hold. Frenar al restaurar dejaría Pitch en un valor que nadie puso; el
    /// pool que suena ya acota al borde de MIDI lo que no quepa.
    func restoring(_ parameter: TrackParameter, to value: Int) -> Cycle {
        switch parameter {
        case .pitch: with(pitchOffset: PitchOffset(value) ?? pitchOffset)
        default: setting(parameter, to: value)
        }
    }
}
