import Engine

/// Qué decide si un Step dispara.
///
/// **Existe para que dos significados no compartan un `nil`.** Antes esto era un
/// `Track?`, y `nil` quería decir «emite todos los Steps». Pero
/// `TrackHandoff.load()` devuelve `nil` con otro significado —«descarta esta
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
    /// Sin asignaciones, sin locks, sin await.
    func triggers(atStep index: Int) -> Bool {
        switch self {
        case .track(let track): track.triggers(atStep: index)
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
    /// Sin asignaciones, sin locks, sin await.
    public mutating func advance(
        toHorizon horizonNanoseconds: Int64,
        refreshingFrom handoff: TrackHandoff?,
        emit: (_ step: Int, _ pitch: Pitch?, _ groove: Groove, _ offsetNanoseconds: Int64) -> Void
    ) {
        if let published = handoff?.load() {
            material = .track(published)
        }

        for step in lookAhead.advance(toHorizon: horizonNanoseconds) {
            guard material.triggers(atStep: step) else { continue }

            // **El orden importa: primero dispara, después decide si suena.** Un
            // Step que no dispara no es un Pulse omitido, es un silencio del
            // reparto euclidiano, y no debe consumir una tirada. Si la
            // consumiera, mover el knob de Pulses desplazaría las omisiones de
            // un patrón que nadie tocó.
            guard material.groove.probability.sounds(drawingFrom: &random) else { continue }

            emit(
                step,
                material.pitch(atStep: step),
                material.groove,
                lookAhead.timeline.nanosecondOffset(forStep: step)
            )
        }
    }
}
