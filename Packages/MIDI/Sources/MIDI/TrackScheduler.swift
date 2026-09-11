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

    /// Con qué forma y cuánta amplitud se mueve la velocity a lo largo de la
    /// vuelta.
    ///
    /// **El arnés usa el neutro y no modula**, por la misma razón por la que usa
    /// el `Groove` por defecto y no repite: mide la rejilla temporal, no el
    /// material musical. Le da igual con qué fuerza suene mientras suene
    /// siempre.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    var modulation: Modulation {
        switch self {
        case .cycle(let cycle): cycle.modulation
        case .everyStep: .default
        }
    }

    /// Cuántos triggers extra cuelgan de cada Pulse.
    ///
    /// **El arnés usa el neutro y no repite** (FR14), por la misma razón por la
    /// que usa el `Groove` por defecto: mide la rejilla temporal, no el material
    /// musical. Una tirada de repeticiones metería nueve eventos donde el
    /// histograma espera uno y mediría otra cosa.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    var noteRepeater: NoteRepeater {
        switch self {
        case .cycle(let cycle): cycle.noteRepeater
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
/// **La rejilla sigue a la Division del material vigente**, desde
/// `division-hot-grid_20260911`. Hasta entonces la fijaba la `MusicalTimeline`
/// con la que se construía este valor y no se volvía a leer. Ahora cambia por
/// las dos puertas por las que cambia el material: el snapshot, al principio de
/// cada ventana, y el avance de Cycle, dentro de ella. En las dos se reancla en
/// un Step que todavía no ha salido, así que lo ya entregado se queda como
/// sonó y ningún Step se pierde ni se repite.
///
/// > **El precio, aceptado a sabiendas.** Un Track reanclado mide desde su
/// > propio corte y no desde el origen de Play, así que deja de estar en fase
/// > con los demás. Está en *Known Limitations* del spec del track; para
/// > volver a alinearlos está Play.
public struct TrackScheduler {

    /// Material vigente. Se conserva entre ventanas: si una lectura del snapshot
    /// se descarta, se sigue tocando esto en lugar de callar o inventar.
    public private(set) var material: SchedulerMaterial

    private var lookAhead: LookAheadScheduler

    /// Cuánto dura un Step, que es contra lo que se miden los dos parámetros
    /// temporales.
    ///
    /// **Se recalcula cuando la rejilla se reancla, y solo entonces.** Hasta el
    /// 2026-09-11 era un `let` fijado al construir, porque la rejilla no
    /// cambiaba nunca; desde que la Division se sigue en caliente
    /// (`division-hot-grid_20260911`) sí cambia, y dejar este valor congelado
    /// era justo la mitad del defecto: el gate lo recalculaba `Transport` por
    /// nota contra la Division viva y el espaciado se quedaba en la vieja.
    ///
    /// Sigue sin convertirse en cada ventana: la conversión de coma flotante
    /// ocurre en el reanclaje, que es raro, y no una vez por ventana para
    /// obtener siempre el mismo número.
    private var stepDurationNanoseconds: Int64

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
    private var previousCursor = 0

    /// Primer Step de la vuelta en curso.
    ///
    /// **La vuelta se mide desde aquí y no con un módulo sobre el índice
    /// absoluto**, para que cada Cycle recorra una vuelta de **su** longitud: si
    /// el Cycle A mide 16 Steps y el B mide 12, el B tiene que durar doce y no
    /// los ocho que quedaran hasta el múltiplo siguiente de dieciséis.
    private var turnStartStep: Int

    /// Que el Step siguiente abra vuelta nueva desde el Cycle 1.
    ///
    /// **Existe porque el límite de compás cae encima de un cierre de vuelta.**
    /// Cuando entra un Pattern armado (FR8) hay que empezar por su primer Cycle,
    /// y poner el cursor a cero no basta: el Step siguiente vería que la vuelta
    /// se cerró —`turnStartStep` sigue donde estaba— y avanzaría el cursor otra
    /// vez, dejando el Pattern nuevo empezando por su segundo Cycle. Anclar la
    /// vuelta al Step que llega es lo que evita ese avance de más.
    private var restartsTurnAtNextStep = false

    /// Salida lock-free del cursor para la interfaz. `nil` en los schedulers
    /// aislados y en la vía directa del arnés.
    private var playbackClock: CyclePlaybackClock?
    private var playbackTrack = 0

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
        self.windowBudgetNanoseconds = material.groove.advanceBudgetNanoseconds(
            forStep: Int64(timeline.stepDurationNanoseconds))
        self.turnStartStep = startingStep
        self.playbackClock = nil
    }

    mutating func reportPlayback(to clock: CyclePlaybackClock, track index: Int) {
        playbackClock = clock
        playbackTrack = index
        clock.publish(
            track: index, cycle: cursor, previousCycle: cursor, earlierCycle: cursor,
            turnStartStep: turnStartStep)
        // Sin reanclar, la vigente y la anterior son la de Play (FR11).
        clock.publishGrid(track: index, current: lookAhead.timeline, previous: lookAhead.timeline)
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
        adoptGridOfCurrentMaterial()
    }

    /// Pone la rejilla en la Division del material vigente, si no lo estaba ya.
    ///
    /// **Es todo el arreglo de `division-hot-grid_20260911`.** La rejilla dejó
    /// de ser lo que hubiera al pulsar Play y pasó a ser función del material:
    /// mientras el snapshot traiga la misma Division esto no hace nada, y en
    /// cuanto traiga otra, la rejilla la adopta anclando en el Step aún no
    /// entregado (FR1, FR6).
    ///
    /// **La comparación es lo que se paga por ventana**, no el reanclaje: dos
    /// enteros, y casi siempre iguales (NFR2). `Division` es `Equatable` sobre
    /// numerador y denominador, así que no hay nada que asignar.
    ///
    /// **Sin Cycle no hay Division que seguir**, y ahí está la vía del arnés: el
    /// material `.everyStep` mide la rejilla que le dio su configuración y no
    /// debe moverse de ella (FR18).
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private mutating func adoptGridOfCurrentMaterial() {
        guard let division = divisionToAdopt else { return }

        let previous = lookAhead.timeline
        lookAhead.rebase(to: division, delayedBy: anchorDelay(adopting: division))
        stepDurationNanoseconds = Int64(lookAhead.timeline.stepDurationNanoseconds)
        publishGrid(replacing: previous)
    }

    /// Le cuenta a la interfaz con qué rejilla se mide ahora, y cuál había
    /// antes (FR10). Sin reloj de reproducción —schedulers aislados, arnés— no
    /// hace nada.
    ///
    /// Realtime: llamado desde el hilo del scheduler, solo al reanclar.
    /// Sin asignaciones, sin locks, sin await.
    private func publishGrid(replacing previous: MusicalTimeline) {
        playbackClock?.publishGrid(
            track: playbackTrack, current: lookAhead.timeline, previous: previous)
    }

    /// El presupuesto de adelanto con el que se decidió la ventana en curso, o
    /// la última: es contra lo que se colocó la marca de agua.
    private var windowBudgetNanoseconds: Int64

    /// Cuánto retrasar el ancla al adoptar `division`.
    ///
    /// **Cero salvo con Delay negativo y un presupuesto que crece**, que es la
    /// enmienda de FR17. La marca de agua se colocó con el presupuesto de la
    /// ventana: el Step aún no entregado cae como mucho eso por delante del
    /// horizonte ya servido. Si la rejilla nueva le pide adelantarse más, su
    /// instante de emisión caería antes del presente. Retrasar el ancla lo que
    /// crece el presupuesto deja ese Step sonando cuando sonaba.
    ///
    /// Si el presupuesto encoge no se adelanta nada: el Step suena algo más
    /// tarde, nunca en el pasado.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await. La conversión de coma flotante
    /// ocurre solo al reanclar.
    private func anchorDelay(adopting division: Division) -> Int64 {
        let step = Int64(
            MusicalTimeline(tempo: lookAhead.timeline.tempo, division: division)
                .stepDurationNanoseconds)
        return max(
            0, material.groove.advanceBudgetNanoseconds(forStep: step) - windowBudgetNanoseconds)
    }

    /// Lo mismo, pero a mitad de ventana: ancla en `step`, que el rango en curso
    /// anunció y todavía no ha salido, y devuelve ahí la marca de agua.
    ///
    /// Devuelve si reancló, que es lo que le dice a `advance` que el resto del
    /// rango ya no vale.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private mutating func adoptGridOfCurrentMaterial(reopeningAt step: Int) -> Bool {
        guard let division = divisionToAdopt else { return false }

        let previous = lookAhead.timeline
        lookAhead.rebase(
            to: division, reopeningAt: step, delayedBy: anchorDelay(adopting: division))
        stepDurationNanoseconds = Int64(lookAhead.timeline.stepDurationNanoseconds)
        publishGrid(replacing: previous)
        return true
    }

    /// La Division del material vigente si la rejilla no la tiene ya, o `nil`
    /// si no hay nada que adoptar —la misma, o la vía del arnés, sin Cycle—.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private var divisionToAdopt: Division? {
        guard let division = material.cycle?.shape.division,
            division != lookAhead.timeline.division
        else { return nil }
        return division
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
        if let cycle = track.cycle(at: cursor) ?? track.cycle(at: 0) {
            material = .cycle(cycle)
        }
        adoptGridOfCurrentMaterial()
    }

    /// Pone la reproducción en el primer Cycle.
    ///
    /// Lo llama Play, que es cuando se construye todo esto (FR6): pulsar Play
    /// dos veces tiene que reproducir el mismo desarrollo, y eso exige empezar
    /// siempre por el mismo Cycle.
    mutating func restartCycles() {
        cursor = 0
        previousCursor = 0
        // El Cycle 1 se pide por índice y no con `track.current`: `current` mira
        // el cursor **del snapshot**, que puede estar en cualquier sitio. El que
        // manda aquí es el de este hilo, que se acaba de poner a cero.
        if let track, let first = track.cycle(at: 0) { material = .cycle(first) }
        playbackClock?.publish(
            track: playbackTrack, cycle: cursor, previousCycle: cursor, earlierCycle: cursor,
            turnStartStep: turnStartStep)
    }

    /// Pone la reproducción en el primer Cycle **y ancla la vuelta al Step que
    /// venga**.
    ///
    /// Es lo que llama la adopción de un Pattern armado (FR8), y se diferencia
    /// de `restartCycles()` en que aquélla la llama Play, cuando la rejilla
    /// arranca de cero y no hay ninguna vuelta en curso que reanclar.
    mutating func restartCyclesAtNextStep() {
        cursor = 0
        previousCursor = 0
        restartsTurnAtNextStep = true
        if let track, let first = track.cycle(at: 0) { material = .cycle(first) }
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
        emitRepetition: (
            (
                _ source: Cycle?, _ step: Int, _ pitch: Pitch?, _ velocity: Velocity,
                _ gateNanoseconds: Int64, _ offsetNanoseconds: Int64
            ) -> Void
        )? = nil,
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
        windowBudgetNanoseconds = advanceBudgetNanoseconds
        var target = horizonNanoseconds + windowBudgetNanoseconds

        var steps = lookAhead.advance(toHorizon: target)
        while let step = steps.popFirst() {
            if restartsTurnAtNextStep {
                restartsTurnAtNextStep = false
                turnStartStep = step
            } else if advanceCycleIfTheTurnClosed(before: step),
                adoptGridOfCurrentMaterial(reopeningAt: step)
            {
                // **El Cycle entrante trae otra Division: se trunca el rango y
                // se reentra** (FR3, FR7). El rango se calculó con la rejilla
                // vieja, así que lo que queda de él no es lo que cabe con la
                // nueva: con una Division más lenta sobran Steps, que saldrían
                // lejos por delante del horizonte; con una más rápida faltan, y
                // saldrían en la ventana siguiente para un instante que ya se
                // entregó. Emitir el resto «ya anclado» tiene los dos defectos.
                //
                // Reentrar no los tiene. La rejilla nueva ancla en este Step y
                // el resto se recalcula **con el presupuesto nuevo**, que es el
                // que la rejilla nueva pide: con Delay negativo, el ancla se
                // retrasó lo que el presupuesto creció, y medir contra el viejo
                // dejaría fuera de la ventana al propio Step del corte. El Step
                // en curso sigue su camino con la rejilla nueva y el material
                // nuevo, que es FR5 de la rebanada de Cycles. `turnStartStep` ya
                // apunta aquí, así que la reentrada no vuelve a avanzar el
                // cursor.
                //
                // El coste solo se paga cuando el Cycle entrante declara otra
                // Division (NFR2): dos enteros de un rango, sin asignar nada.
                windowBudgetNanoseconds = advanceBudgetNanoseconds
                target = horizonNanoseconds + windowBudgetNanoseconds
                steps = lookAhead.advance(toHorizon: target)

                // **El Step del corte puede no caber ya en esta ventana**, y
                // entonces espera a la suya. Pasa cuando el Cycle entrante
                // adelanta menos que el que sale: el presupuesto encoge y el
                // horizonte queda por detrás del Step. No se pierde, porque la
                // marca de agua apunta a él, ni avanza el cursor dos veces,
                // porque `turnStartStep` también. Emitirlo aquí sí lo repetiría
                // en la ventana siguiente.
                guard steps.popFirst() == step else { continue }
            }
            let cycleStep = step - turnStartStep

            guard material.triggers(atStep: cycleStep) else { continue }

            // **El orden importa: primero dispara, después decide si suena.** Un
            // Step que no dispara no es un Pulse omitido, es un silencio del
            // reparto euclidiano, y no debe consumir una tirada. Si la
            // consumiera, mover el knob de Pulses desplazaría las omisiones de
            // un patrón que nadie tocó.
            // **Una tirada por evento, y el Pulse va primero** (FR13). La tirada
            // se consume aunque el Cycle esté mudo, como antes de la rebanada:
            // llenarle el pool mientras suena no debe mover las omisiones.
            let pulseSounds = material.groove.probability.sounds(drawingFrom: &random)

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
            let groove = material.groove
            let pulseOffset =
                lookAhead.timeline.nanosecondOffset(forStep: step)
                + groove.shiftNanoseconds(
                    atStep: cycleStep, stepDurationNanoseconds: stepDurationNanoseconds)

            // **La modulación se compone aquí, con `cycleStep` y el anillo ya a
            // mano.** La fase sale del índice dentro de la vuelta, así que un
            // ciclo de modulación dura exactamente una vuelta y cada Track
            // modula a su velocidad — no hay reloj de modulación que sincronizar
            // (FR4).
            //
            // **Va después de la tirada de Probability y del cálculo del
            // instante, y no antes.** Un Step callado o un Step que no dispara
            // consumen igualmente su posición del ciclo, porque la fase depende
            // del índice y nunca de si hubo nota (FR8): atarla a una tirada
            // aleatoria haría que «un ciclo por vuelta» dejara de ser cierto.
            // Como el valor sale del índice y no de un acumulador, eso sale
            // gratis: no hay nada que avanzar.
            //
            // **Con `accent` en 0 devuelve el mismo `Groove`**, sin pasar por la
            // onda ni por el acotado, que es el criterio 1 de la rebanada.
            let voiced = groove.modulated(
                by: material.modulation, atStep: cycleStep, of: material.stepCount ?? 1)

            if pulseSounds, material.emitsAnything {
                emit(
                    material.cycle,
                    step,
                    material.pitch(atStep: cycleStep),
                    voiced,
                    pulseOffset
                )
            }

            // **Un Pulse callado no se lleva sus repeticiones.** Son eventos
            // independientes, así que la tirada se hace por cada uno: bajar
            // Probability con Repeats altos perfora la textura en vez de borrar
            // tiradas enteras.
            emitRepetitions(
                after: cycleStep, at: step, offset: pulseOffset, emit: emitRepetition)
        }
    }

    /// Cuelga del Pulse las repeticiones que quepan antes del corte.
    ///
    /// **Con Repeats en 0 no se ejecuta nada de aquí**, que es lo que sostiene
    /// FR16: se sale por el primer `guard`, antes de calcular ningún hueco. Es
    /// también NFR3 — el coste crece con lo que suena.
    ///
    /// **Las repeticiones van siempre después del Pulse**, así que no adelantan
    /// ningún instante y `advanceBudgetNanoseconds` no cambia: el presupuesto de
    /// adelanto sigue siendo cosa de Delay.
    ///
    /// **La tirada arranca en el Pulse ya desplazado.** El offset que llega es
    /// el del Pulse con su Timing y su Delay dentro, y los huecos se acumulan
    /// desde ahí: ninguna repetición recibe swing propio, porque el swing opera
    /// sobre la rejilla de Steps y no sobre la de repeticiones (FR10).
    ///
    /// **La altura es la del Pulse** (FR11): sale de `pitch(atStep:)`, que es
    /// función de la posición en el anillo, así que un ratchet no acelera el
    /// recorrido del pool.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin coma flotante, sin arrays temporales: un bucle
    /// acotado por Repeats, que llega hasta ocho.
    private mutating func emitRepetitions(
        after cycleStep: Int,
        at step: Int,
        offset pulseOffset: Int64,
        emit: (
            (
                _ source: Cycle?, _ step: Int, _ pitch: Pitch?, _ velocity: Velocity,
                _ gateNanoseconds: Int64, _ offsetNanoseconds: Int64
            ) -> Void
        )?
    ) {
        guard let emit, let cycle = material.cycle else { return }
        // Se pregunta al material y no al Cycle, para que la vía del arnés tenga
        // una respuesta escrita —el neutro— y no dependa de que `cycle` sea nil.
        let repeater = material.noteRepeater
        let count = repeater.repeats.count
        guard count > 0 else { return }

        // **El corte y el hueco base leen el mismo Step** (FR15 de
        // `division-hot-grid_20260911`). Mientras la rejilla se congelaba en
        // Play, el corte se medía con el Step de entonces y el hueco con la
        // Division viva, y al girar el knob los dos lados discrepaban: con
        // 1/16 → 1/8 el hueco salía la mitad de largo. Desde que
        // `stepDurationNanoseconds` se recalcula al reanclar, los dos salen de
        // la rejilla vigente; lo fija `RepeatWindowDivisionTests`.
        let window = cycle.repeatWindowNanoseconds(
            fromStep: cycleStep, stepDurationNanoseconds: stepDurationNanoseconds)
        let base = repeater.time.gapNanoseconds(
            forStep: stepDurationNanoseconds, division: cycle.shape.division)
        let pitch = cycle.pitch(atStep: cycleStep)

        // **Las repeticiones heredan la velocity ya modulada del Pulse.** Ramp
        // recorre las repeticiones de un Pulse y `accent` recorre la vuelta del
        // anillo: son dos ejes distintos, así que se componen en vez de
        // excluirse. Si no lo hicieran, subir Repeats diluiría el acento —el
        // Pulse sonaría acentuado y su tirada no—, que es justo lo contrario de
        // lo que las dos cosas prometen.
        //
        // La Pre Spec pone a Ramp «relativo a la Velocity general del Track», y
        // la Velocity general de **este Step** es la modulada.
        let groove = cycle.groove.modulated(
            by: cycle.modulation, atStep: cycleStep, of: cycle.shape.steps.count)

        var elapsed: Int64 = 0
        for index in 1...count {
            let gap = repeater.pace.gapNanoseconds(forRepetition: index, of: count, base: base)
            elapsed += gap

            // **Estrictamente antes del corte.** Una repetición que cayera justo
            // en el Pulse siguiente sonaría encima de él, que es la nota que el
            // corte existe para no duplicar.
            //
            // **El corte se decide antes que la tirada**, con el mismo criterio
            // que ya separa «primero dispara, después decide si suena»: una
            // repetición descartada no consume aleatoriedad, así que girar Time
            // o Pace no desplaza las omisiones de un patrón que nadie tocó.
            guard elapsed < window else { return }

            guard groove.probability.sounds(drawingFrom: &random) else { continue }

            emit(
                cycle,
                step,
                pitch,
                repeater.ramp.velocity(forRepetition: index, of: count, from: groove.velocity),
                groove.sustain.gateNanoseconds(over: gap),
                pulseOffset + elapsed
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
    /// Devuelve si la vuelta se cerró, que es el único momento en que el
    /// material puede haber traído otra Division: así la comparación se hace
    /// una vez por vuelta y no una por Step (NFR2).
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private mutating func advanceCycleIfTheTurnClosed(before step: Int) -> Bool {
        guard let track, let stepCount = material.stepCount else { return false }
        guard step - turnStartStep >= stepCount else { return false }

        let earlierCursor = previousCursor
        previousCursor = cursor
        turnStartStep = step
        cursor = Track.cursorAfter(cursor, activeCount: track.activeCount)
        if let cycle = track.cycle(at: cursor) { material = .cycle(cycle) }
        playbackClock?.publish(
            track: playbackTrack, cycle: cursor, previousCycle: previousCursor,
            earlierCycle: earlierCursor,
            turnStartStep: turnStartStep)
        return true
    }
}
