import Engine

/// Qué decide si un Step dispara.
///
/// **Existe para que dos significados no compartan un `nil`.** Antes esto era un
/// `Track?`, y `nil` quería decir «emite todos los Steps». Pero
/// `PatternHandoff.load()` devuelve `nil` con otro significado —«descarta esta
/// lectura»—, así que enchufar uno en el otro convertía un descarte en una
/// ráfaga de notas a densidad máxima. Con dos casos con nombre, esa confusión no
/// se puede escribir.
public enum SchedulerMaterial: Equatable, Sendable {

    /// El material musical de un Track: dispara donde diga su Shape.
    case track(Track)

    /// Todos los Steps disparan.
    ///
    /// Es el modo del arnés de medición, que mide la rejilla temporal y no el
    /// material musical: ahí un reparto euclidiano solo quitaría muestras al
    /// histograma.
    case everyStep

    /// Altura del arnés de medición.
    ///
    /// El arnés mide la rejilla temporal, no el material musical: necesita que
    /// suene *algo* y le da igual qué. Es una constante suya, no un valor
    /// musical, y por eso vive aquí y no en `Engine`.
    static let measurementPitch = Pitch(48)!

    /// Realtime: llamado desde el hilo del scheduler.
    /// Determines whether the material triggers at the specified step.
    /// - Parameter index: The step index to evaluate.
    /// - Returns: `true` if the material triggers at the step, `false` otherwise.
    func triggers(atStep index: Int) -> Bool {
        switch self {
        case .track(let track): track.triggers(atStep: index)
        case .everyStep: true
        }
    }

    /// Si este material puede llegar a sonar.
    ///
    /// Un Track con el pool vacío dispara sus Pulses y no tiene nada que emitir,
    /// así que programarlo es trabajo tirado: es lo que hace que el coste crezca
    /// con los Tracks que suenan y no con dieciséis siempre (NFR3). El arnés de
    /// medición siempre suena — mide la rejilla, no el material—.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    var emitsAnything: Bool {
        switch self {
        case .track(let track): !track.pool.isEmpty
        case .everyStep: true
        }
    }

    /// Cómo se interpreta lo que suena.
    ///
    /// **El arnés usa el default y no el suyo propio.** Mide la rejilla
    /// temporal, no el material musical: le da igual con qué dinámica suene
    /// mientras suene siempre. Darle un Groove propio sería inventarle un valor
    /// musical a algo que no lo tiene.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    var groove: Groove {
        switch self {
        case .track(let track): track.groove
        case .everyStep: .default
        }
    }

    /// Con qué altura suena el Step.
    ///
    /// **Quien conoce el material decide la altura.** Podría hacerlo el
    /// emisor, pero entonces habría que pasarle el Track entero en cada pulso o
    /// dejarle una copia que se desincronizara del snapshot. Aquí ya está el
    /// material vigente, recogido una vez por ventana.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    func pitch(atStep index: Int) -> Pitch? {
        switch self {
        case .track(let track): track.pitch(atStep: index)
        case .everyStep: Self.measurementPitch
        }
    }
}

/// Decide qué Steps de un Track se emiten en cada ventana, y recoge los
/// snapshots que se publiquen mientras suena.
///
/// **Por qué existe como tipo aparte.** `LookAheadScheduler` sabe *qué Steps*
/// caen en la ventana; el Track sabe *cuáles de ellos disparan*. Juntarlo aquí
/// —y no dentro del hilo— deja el relevo de snapshot en un valor al que se le
/// puede dar el horizonte a mano. Así «el snapshot se recoge en la ventana
/// siguiente» es un test determinista y no una carrera contra el reloj.
///
/// **Qué se omite, y qué no.** Probability decide sobre los Pulses que ya
/// dispararon, nunca sobre los Steps que el reparto euclidiano deja vacíos: un
/// silencio del reparto no es una omisión y no consume aleatoriedad.
///
/// **La altura no depende de la omisión.** Sale de `pulseOrdinal(atStep:)`, que
/// es función de la posición en el anillo: bajar Probability perfora la línea y
/// no la ralentiza. Es también lo que evita un contador mutable más en el camino
/// de tiempo real.
///
/// **Dónde se recoge el snapshot.** Una vez por ventana, antes de recorrerla,
/// nunca a mitad. Un cambio a media ventana partiría el patrón dentro del mismo
/// horizonte y haría imposible razonar sobre qué Steps ya se habían entregado.
///
/// **Lo que el snapshot todavía no puede cambiar en caliente: Division.**
/// La rejilla temporal —cuándo cae cada Step— la fija la `MusicalTimeline` con
/// la que se construye este valor, y no se vuelve a leer. Cambiar la Division de
/// un Track publicado altera la duración del Step, así que reubicaría todos los
/// Steps futuros respecto a un origen que ya pasó: hace falta rebasar la línea
/// de tiempo en un límite de Step, no solo leer un valor nuevo. En esta rebanada
/// no hay entrada de control y ningún parámetro es editable, así que no se puede
/// provocar; llega con el track de entrada de control. Steps, Pulses y Rotate sí
/// cambian en caliente y están cubiertos por tests.
public struct TrackScheduler {

    /// Material vigente. Se conserva entre ventanas: si una lectura del snapshot
    /// se descarta, se sigue tocando esto en lugar de callar o inventar.
    public private(set) var material: SchedulerMaterial

    private var lookAhead: LookAheadScheduler

    /// Cuánto dura un Step, que es contra lo que se miden los dos parámetros
    /// temporales.
    ///
    /// **Se calcula una vez, al construir.** La rejilla la fija la
    /// `MusicalTimeline` con la que nace este valor y no se vuelve a leer —está
    /// documentado arriba—, así que la duración tampoco cambia. Convertirla en
    /// cada ventana sería aritmética de coma flotante repetida en el hilo del
    /// scheduler para obtener siempre el mismo número.
    private let stepDurationNanoseconds: Int64

    /// El generador que decide qué Pulse concreto se omite.
    ///
    /// **Vive aquí y no en `Track` porque tiene estado mutable.** El snapshot
    /// tiene que seguir siendo trivial —`_isPOD(Track.self)` lo vigila— y
    /// meterlo dentro haría además que dos hilos mutaran lo mismo. Este valor,
    /// en cambio, lo toca un solo hilo: el del scheduler.
    ///
    /// **Se siembra al construir, y construir es lo que hace Play.** De ahí sale
    /// la promesa de `tech-stack.md`: pulsar Play dos veces reproduce la misma
    /// secuencia de omisiones. Dentro de una pasada avanza por Pulse, así que
    /// dos vueltas del anillo no omiten lo mismo.
    private var random: SeededRandom

    public init(
        timeline: MusicalTimeline,
        material: SchedulerMaterial = .everyStep,
        startingAtStep startingStep: Int = 0,
        seed: UInt64 = SeededRandom.defaultSeed
    ) {
        self.material = material
        self.lookAhead = LookAheadScheduler(timeline: timeline, startingAtStep: startingStep)
        self.random = SeededRandom(seed: seed)
        self.stepDurationNanoseconds = Int64(timeline.stepDurationNanoseconds)
    }

    /// Sustituye el material sin tocar la posición en la rejilla.
    ///
    /// Es lo que hace `advance(toHorizon:refreshingFrom:)` cuando el handoff
    /// trae algo, expuesto aparte para que `PatternScheduler` pueda leer el
    /// snapshot **una sola vez** y repartirlo entre los dieciséis: si cada uno
    /// leyera el suyo, dos Tracks podrían tocar material de publicaciones
    /// distintas.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    mutating func refresh(with track: Track) {
        material = .track(track)
    }

    /// Cuánto tiempo hay que reservar por delante para que ningún evento
    /// adelantado se pida para un instante que ya pasó.
    ///
    /// Es el presupuesto del material **vigente**, así que cambia cuando cambia
    /// el snapshot. Lo consultan los dos sitios que lo necesitan: este valor,
    /// para ampliar su horizonte de selección en cada ventana; y
    /// `SchedulerThread`, una sola vez al arrancar, para desplazar el origen de
    /// la rejilla.
    ///
    /// Con Delay ≥ 0 vale cero y nada cambia respecto a antes de la rebanada 6.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public var advanceBudgetNanoseconds: Int64 {
        material.groove.advanceBudgetNanoseconds(forStep: stepDurationNanoseconds)
    }

    /// Recoge el snapshot pendiente y emite los Steps que disparan hasta el
    /// horizonte.
    ///
    /// `emit` recibe el índice de Step, la altura que le toca —`nil` con el pool
    /// vacío—, el Groove con que interpretarla y su offset en nanosegundos
    /// respecto al origen de la línea de tiempo. El cierre no escapa, así que no
    /// hay nada que asignar para llamarlo.
    ///
    /// **El Groove viaja por el mismo sitio que la altura, y no por otro.**
    /// Quien emite necesita los dos para construir el par de mensajes, y los dos
    /// tienen que venir del **mismo** snapshot: leerlos de sitios distintos
    /// dejaría que una altura del Track nuevo sonara con la dinámica del viejo
    /// en el borde de una ventana.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Advances the scheduler through the requested horizon and emits steps that trigger and pass the material's probability.
    /// - Parameters:
    ///   - horizon: The timeline horizon, in nanoseconds.
    ///   - handoff: An optional pending track snapshot to apply before processing the horizon.
    ///   - emit: A closure called with each emitted step, its pitch, groove, and timeline-relative offset.
    ///
    /// Steps that do not trigger do not consume a probability draw.
    public mutating func advance(
        toHorizon horizonNanoseconds: Int64,
        refreshingFrom handoff: PatternHandoff?,
        emit: (_ step: Int, _ pitch: Pitch?, _ groove: Groove, _ offsetNanoseconds: Int64) -> Void
    ) {
        if let published = handoff?.load(), let track = published.track(at: 0) {
            // > **Puente de la v2, fase 2.** El handoff ya trae los dieciséis
            // > Tracks y este scheduler todavía emite uno. La fase 3 le da el
            // > recorrido; hasta entonces lee el Track 1, que es lo que la
            // > interfaz edita.
            material = .track(track)
        }

        // **El horizonte se amplía con el presupuesto de adelanto.** Sin esto,
        // un Step con Delay negativo se calcularía unos milisegundos antes de su
        // rejilla y se pediría su emisión hasta un Step antes de eso: en el
        // pasado, y en cada vuelta del anillo. Se relee del snapshot aquí y no
        // se fija al construir porque Delay se gira mientras suena.
        //
        // Con Delay ≥ 0 el presupuesto es cero y el horizonte es exactamente el
        // de antes de la rebanada 6.
        let budget = advanceBudgetNanoseconds

        for step in lookAhead.advance(toHorizon: horizonNanoseconds + budget) {
            guard material.triggers(atStep: step) else { continue }

            // **El orden importa: primero dispara, después decide si suena.** Un
            // Step que no dispara no es un Pulse omitido, es un silencio del
            // reparto euclidiano, y no debe consumir una tirada. Si la
            // consumiera, mover el knob de Pulses desplazaría las omisiones de
            // un patrón que nadie tocó.
            guard material.groove.probability.sounds(drawingFrom: &random) else { continue }

            // El instante de emisión es el de la rejilla más lo que Groove lo
            // aparta. Los dos salen del mismo snapshot, recogido una vez por
            // ventana: leerlos de sitios distintos dejaría que un Step sonara
            // con el desplazamiento de un Track que ya no está.
            let groove = material.groove
            emit(
                step,
                material.pitch(atStep: step),
                groove,
                lookAhead.timeline.nanosecondOffset(forStep: step)
                    + groove.shiftNanoseconds(
                        atStep: step, stepDurationNanoseconds: stepDurationNanoseconds)
            )
        }
    }
}
