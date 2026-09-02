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
    case cycle(Cycle)

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

    /// El Cycle de este material, o `nil` en la vía del arnés.
    ///
    /// Lo necesita quien emite —el canal y la Division son datos del Cycle— y lo
    /// necesita el recorrido, para saber cuántos Steps mide la vuelta en curso.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    var cycle: Cycle? {
        switch self {
        case .cycle(let cycle): cycle
        case .everyStep: nil
        }
    }

    /// Cuántos Steps mide una vuelta de este material, o `nil` si no tiene
    /// anillo: el arnés mide la rejilla y no da vueltas.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    var stepCount: Int? {
        switch self {
        case .cycle(let cycle): cycle.shape.steps.count
        case .everyStep: nil
        }
    }

    /// Realtime: llamado desde el hilo del scheduler.
    /// Determines whether the material triggers at the specified step.
    /// - Parameter index: The step index to evaluate.
    /// - Returns: `true` if the material triggers at the step, `false` otherwise.
    func triggers(atStep index: Int) -> Bool {
        switch self {
        case .cycle(let cycle): cycle.triggers(atStep: index)
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
        case .cycle(let cycle): !cycle.pool.isEmpty
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
        case .cycle(let cycle): cycle.groove
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
        case .cycle(let cycle): cycle.pitch(atStep: index)
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
/// Steps, Pulses y Rotate sí cambian en caliente y están cubiertos por tests.
///
/// > **Con Cycles hay una vía más de llegar aquí, y queda acotada.** Desde la
/// > rebanada 3 de la v2, dos Cycles de un mismo Track pueden declarar Divisions
/// > distintas. No se aplica: el Cycle nuevo suena con todo lo suyo —Steps,
/// > Pulses, Rotate, pool, marco tonal, Groove y canal— sobre la rejilla del
/// > Cycle que estuviera vigente al pulsar Play. Resolverlo exigiría rebasar la
/// > línea de tiempo por Track, que es romper el invariante que mantiene en fase
/// > a los dieciséis: todas las rejillas se miden contra el mismo origen. Está
/// > en *Known Limitations* del spec del track `cycles_20260901`, y fijado con
/// > tests en `WhatChangesWithTheCycleTests`.
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
    /// **Vive aquí y no en `Cycle` porque tiene estado mutable.** El snapshot
    /// tiene que seguir siendo trivial —`_isPOD(Cycle.self)` lo vigila— y
    /// meterlo dentro haría además que dos hilos mutaran lo mismo. Este valor,
    /// en cambio, lo toca un solo hilo: el del scheduler.
    ///
    /// **Se siembra al construir, y construir es lo que hace Play.** De ahí sale
    /// la promesa de `tech-stack.md`: pulsar Play dos veces reproduce la misma
    /// secuencia de omisiones. Dentro de una pasada avanza por Pulse, así que
    /// dos vueltas del anillo no omiten lo mismo.
    private var random: SeededRandom

    /// El Track vigente, cuando lo hay: es de donde salen los Cycles y cuántos
    /// están activos.
    ///
    /// `nil` es la vía del arnés de medición, que mide la rejilla y no tiene
    /// Track detrás.
    private var track: Track?

    /// Por qué Cycle va la reproducción.
    ///
    /// **Vive aquí y no en el snapshot, por la misma razón que `random`.** El
    /// cursor que trae un Track publicado es viejo por construcción: lo escribe
    /// el hilo principal, que no sabe —ni puede saber— por dónde va la
    /// reproducción. Tomarlo del snapshot devolvería el desarrollo al principio
    /// cada vez que alguien girase un knob.
    ///
    /// Del snapshot se toma el **material** y **cuántos Cycles hay activos**;
    /// por cuál va, lo decide este hilo.
    private var cursor = 0

    /// Primer Step de la vuelta en curso.
    ///
    /// **La vuelta se mide desde aquí y no con un módulo sobre el índice
    /// absoluto**, para que cada Cycle recorra una vuelta de **su** longitud: si
    /// el Cycle A mide 16 Steps y el B mide 12, el B tiene que durar doce y no
    /// los ocho que quedaran hasta el múltiplo siguiente de dieciséis.
    private var turnStartStep: Int

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
        self.turnStartStep = startingStep
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
    mutating func refresh(with cycle: Cycle) {
        material = .cycle(cycle)
    }

    /// Sustituye el Track sin tocar ni la posición en la rejilla ni el cursor de
    /// reproducción.
    ///
    /// **Del snapshot se toma el material y cuántos Cycles hay activos; por cuál
    /// va la reproducción lo sigue decidiendo este hilo.** El cursor que trae el
    /// Track publicado es viejo por construcción —lo escribe el hilo principal,
    /// que no sabe por dónde va el sonido—, así que hacerle caso devolvería el
    /// desarrollo al principio en cada giro de knob.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    mutating func refresh(with track: Track) {
        self.track = track
        material = .cycle(track.cycle(at: cursor) ?? track.current)
    }

    /// Pone la reproducción en el primer Cycle.
    ///
    /// Lo llama Play, que es cuando se construye todo esto (FR6): pulsar Play
    /// dos veces tiene que reproducir el mismo desarrollo, y eso exige empezar
    /// siempre por el mismo Cycle.
    mutating func restartCycles() {
        cursor = 0
        if let track { material = .cycle(track.current) }
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
        emit: (
            _ source: Cycle?, _ step: Int, _ pitch: Pitch?, _ groove: Groove,
            _ offsetNanoseconds: Int64
        ) -> Void
    ) {
        if let published = handoff?.load(), let cycle = published.cycle(at: 0) {
            // > **Puente de la v2, fase 2.** El handoff ya trae los dieciséis
            // > Tracks y este scheduler todavía emite uno. La fase 3 le da el
            // > recorrido; hasta entonces lee el Track 1, que es lo que la
            // > interfaz edita.
            material = .cycle(cycle)
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
            advanceCycleIfTheTurnClosed(before: step)

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
            // **Si el Cycle vigente no tiene material, no se emite** (NFR3 de
            // la rebanada 1: el coste crece con lo que suena). Se pregunta aquí
            // y no una vez por ventana porque desde que el Cycle avanza en el
            // límite de vuelta, el material puede cambiar dentro de la ventana:
            // un Track que arranca mudo y deja de serlo al cambiar de Cycle
            // tiene que sonar en esa misma vuelta.
            //
            // Va **después** de la tirada de Probability y no antes, para no
            // cambiar cuánta aleatoriedad consume un Cycle mudo: si la
            // consumiera distinto, llenarle el pool mientras suena movería las
            // omisiones de un patrón que nadie tocó.
            guard material.emitsAnything else { continue }

            let groove = material.groove
            emit(
                material.cycle,
                step,
                material.pitch(atStep: step),
                groove,
                lookAhead.timeline.nanosecondOffset(forStep: step)
                    + groove.shiftNanoseconds(
                        atStep: step, stepDurationNanoseconds: stepDurationNanoseconds)
            )
        }
    }

    /// Pasa al Cycle siguiente si este Step abre una vuelta nueva.
    ///
    /// **Se llama antes de mirar si el Step dispara**, y esa es toda la
    /// diferencia: FR5 pide que el primer Step de la vuelta nueva ya suene con
    /// el Cycle nuevo, no el segundo. Hacerlo después dejaría el primer Step de
    /// cada vuelta sonando con el material anterior, que es un fallo difícil de
    /// oír y fácil de dejar dentro.
    ///
    /// **La vuelta se mide desde `turnStartStep`**, no con un módulo sobre el
    /// índice absoluto, para que cada Cycle recorra una vuelta de su propia
    /// longitud aunque dos Cycles midan distinto.
    ///
    /// Con un solo Cycle activo, `cursorAfter` devuelve siempre 0 y esto acaba
    /// recalculando el mismo material: no hay avance y nada cambia (FR10). No se
    /// sale antes por ahorrar la comparación, porque `turnStartStep` tiene que
    /// seguir avanzando igual — si no, un Track que subiera a dos Cycles
    /// mientras suena mediría su primera vuelta desde el arranque.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private mutating func advanceCycleIfTheTurnClosed(before step: Int) {
        guard let track, let stepCount = material.stepCount else { return }
        guard step - turnStartStep >= stepCount else { return }

        turnStartStep = step
        cursor = Track.cursorAfter(cursor, activeCount: track.activeCount)
        material = .cycle(track.cycle(at: cursor) ?? track.current)
    }
}
