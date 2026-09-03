import Darwin
import Engine
import Foundation

/// Snapshot inmutable de la configuración con la que corre el scheduler.
///
/// El hilo del scheduler captura este valor al arrancar y no vuelve a leer
/// estado compartido: no hay lock que tomar porque no hay nada mutable que
/// proteger.
///
/// Lo que sí cambia en caliente es el **Track**, y no viaja aquí: llega por
/// `PatternHandoff`, que el hilo consulta una vez por ventana. Esto sigue siendo
/// la configuración de la rejilla —tempo, división y tamaño de la ventana—, que
/// se fija al arrancar el transporte.
public struct SchedulerConfiguration: Sendable, Equatable {

    public let timeline: MusicalTimeline

    /// Cuánto se adelanta el scheduler al calcular eventos.
    ///
    /// Equilibrio doble: una ventana grande absorbe mejor los retrasos del
    /// planificador del SO, pero retrasa la respuesta a un cambio de parámetro.
    /// `product-guidelines.md` exige que un giro de knob se oiga en el Step
    /// siguiente, y eso acota el tamaño por arriba.
    public let lookAheadNanoseconds: Int64

    public init(timeline: MusicalTimeline, lookAheadNanoseconds: Int64 = 20_000_000) {
        self.timeline = timeline
        self.lookAheadNanoseconds = lookAheadNanoseconds
    }
}

/// Hilo dedicado que ejecuta el scheduler look-ahead.
///
/// **Qué hace en cada vuelta:** mira cuánto tiempo ha pasado desde el arranque,
/// añade el horizonte de look-ahead y pide al `LookAheadScheduler` los Steps que
/// caen en esa ventana. Cada Step se entrega con su instante de emisión ya
/// calculado, para que quien lo reciba lo selle con un timestamp futuro.
///
/// **Por qué duerme media ventana:** despertar más a menudo no mejora la
/// precisión —esa la da el timestamp, no el momento del envío— y solo gasta CPU.
/// Despertar menos arriesga perder el borde de la ventana.
///
/// **Reglas de tiempo real.** El bucle no asigna memoria, no toma locks, no usa
/// `await`, no registra logs y no toca SwiftUI. Lo único que comparte con otros
/// hilos es una bandera atómica sin lock.
public final class SchedulerThread: @unchecked Sendable {

    /// Se invoca por cada Step, desde el hilo del scheduler.
    ///
    /// Recibe el índice de Step, la altura, el Groove con que interpretarla y
    /// el instante de emisión en ticks de host. Quien lo implemente hereda las
    /// reglas de tiempo real: sin asignaciones, sin locks, sin logging.
    ///
    /// Altura y Groove salen del **mismo** snapshot, recogido una vez por
    /// ventana: no son dos lecturas que puedan discrepar.
    /// **Desde la v2 llega también el índice del Track**: quien emite necesita
    /// saber por qué canal sale cada nota, y el canal es un dato del Track.
    ///
    /// **Y llega el Track entero, no solo su índice.** Con el índice, quien
    /// emitía tenía que volver al snapshot a buscar el canal y la Division, una
    /// vez por nota. Recibirlo aquí lo deja en una lectura por ventana y, de
    /// paso, garantiza que lo que sella la nota sea el mismo snapshot que la
    /// produjo.
    public typealias StepHandler =
        @Sendable (
            _ track: Int, _ source: Cycle, _ step: Int, _ pitch: Pitch?, _ groove: Groove,
            _ hostTime: UInt64
        ) -> Void

    private let configuration: SchedulerConfiguration
    private let material: SchedulerMaterial

    /// Los dieciséis Tracks, cuando quien arranca el hilo los tiene.
    ///
    /// **`nil` es la vía del arnés de medición**, que mide la rejilla y no el
    /// material: le basta un `SchedulerMaterial` sobre una `MusicalTimeline`. Las
    /// dos vías construyen el mismo `PatternScheduler`, para que lo que se mide
    /// pase por el mismo recorrido que lo que suena.
    private let pattern: Pattern?
    private let handoff: PatternHandoff?

    /// La mezcla vigente: qué Tracks se oyen. `nil` deja sonar a los doce, que
    /// es la vía del arnés de medición.
    private let mutes: MuteMask?
    private let handler: StepHandler

    /// Ancla temporal para el playhead. `nil` cuando nadie la mira.
    private let playhead: PlayheadClock?
    private let cyclePlaybackClock: CyclePlaybackClock?
    private let running = AtomicFlag(false)
    private var thread: Thread?

    /// - Parameters:
    ///   - material: con qué arranca. Por defecto `.everyStep`, que es lo que
    ///     quiere el arnés de medición.
    ///   - handoff: por donde llegan los Tracks publicados mientras suena. `nil`
    ///     deja el material fijo durante toda la reproducción.
    ///   - playhead: dónde se publica el origen temporal para la interfaz.
    ///     `nil` cuando nadie dibuja un playhead — el arnés de medición, por
    ///     ejemplo, que no tiene pantalla.
    public convenience init(
        configuration: SchedulerConfiguration,
        material: SchedulerMaterial = .everyStep,
        handoff: PatternHandoff? = nil,
        playhead: PlayheadClock? = nil,
        pattern: Pattern? = nil,
        mutes: MuteMask? = nil,
        handler: @escaping StepHandler
    ) {
        self.init(
            configuration: configuration,
            material: material,
            handoff: handoff,
            playhead: playhead,
            cyclePlaybackClock: nil,
            pattern: pattern,
            mutes: mutes,
            handler: handler)
    }

    init(
        configuration: SchedulerConfiguration,
        material: SchedulerMaterial = .everyStep,
        handoff: PatternHandoff? = nil,
        playhead: PlayheadClock? = nil,
        cyclePlaybackClock: CyclePlaybackClock?,
        pattern: Pattern? = nil,
        mutes: MuteMask? = nil,
        handler: @escaping StepHandler
    ) {
        self.pattern = pattern
        self.mutes = mutes
        self.configuration = configuration
        self.material = material
        self.handoff = handoff
        self.playhead = playhead
        self.cyclePlaybackClock = cyclePlaybackClock
        self.handler = handler
    }

    public var isRunning: Bool { running.value }

    public func start() {
        guard !running.value else { return }
        running.value = true

        let thread = Thread {
            [
                configuration, material, pattern, handoff, playhead, cyclePlaybackClock,
                mutes, handler, running,
            ] in
            SchedulerThread.run(
                configuration: configuration,
                material: material,
                pattern: pattern,
                handoff: handoff,
                playhead: playhead,
                cyclePlaybackClock: cyclePlaybackClock,
                mutes: mutes,
                handler: handler,
                running: running
            )
        }
        thread.name = "com.toraxh0.scheduler"
        // **La pila por defecto de un `Thread` secundario son 512 KB, y el
        // snapshot ya no cabe con holgura.** Con Cycles el Pattern pasó de
        // 2304 bytes a 37 248, y este hilo lo copia entero en cada ventana: un
        // `load()`, el material que conserva entre ventanas y los temporales del
        // camino son varias decenas de kilobytes por marco donde antes eran unos
        // pocos. Medido el 2026-09-02 sobre el test de concurrencia del handoff
        // —que construye Patterns en bucle, más carga de la que este hilo hace—:
        // desborda con 512 KB y pasa con 1 MB.
        //
        // No cuesta nada tenerla: es reserva de memoria virtual, y las páginas se
        // tocan solo si se usan. Desbordarla, en cambio, es un SIGBUS en el hilo
        // que produce el audio.
        thread.stackSize = 1 << 20
        // Prioridad máxima: el hilo compite con la interfaz por la CPU y el
        // retraso aquí se traduce en eventos perdidos al borde de la ventana.
        thread.qualityOfService = .userInteractive
        thread.threadPriority = 1.0
        self.thread = thread
        thread.start()
    }

    /// Para el bucle.
    ///
    /// **El reloj del playhead se limpia aquí y no al salir del bucle.** `stop()`
    /// baja la bandera y vuelve sin esperar al hilo, que puede tardar hasta
    /// media ventana en verla (ese retraso es el defecto `scheduler-lifecycle`,
    /// abierto y sin integrar). Limpiarlo desde el hilo moribundo tendría dos
    /// consecuencias, y ninguna es aceptable: el playhead seguiría moviéndose
    /// unos milisegundos después de pulsar Stop, y un Play inmediato podría ver
    /// su origen recién publicado **borrado por el hilo anterior al morir**.
    ///
    /// Escribirlo desde aquí no compite con nadie: el hilo del scheduler solo
    /// toca el origen una vez, al arrancar, y este es el hilo de control.
    public func stop() {
        running.value = false
        playhead?.stop()
        thread = nil
    }

    /// Bucle del scheduler.
    ///
    /// Realtime: este es el hilo del scheduler.
    /// Runs the scheduler loop and emits steps within the configured look-ahead window.
    /// - Parameters:
    ///   - configuration: The timeline and look-ahead duration used for scheduling.
    ///   - material: The musical material provided to the scheduler.
    ///   - handoff: An optional source for refreshed track data.
    ///   - playhead: An optional clock started at the scheduler's host-time origin.
    ///   - handler: Receives each scheduled step, its pitch, groove, and host timestamp.
    ///   - running: The flag that controls whether scheduling continues.
    private static func run(
        configuration: SchedulerConfiguration,
        material: SchedulerMaterial,
        pattern: Pattern?,
        handoff: PatternHandoff?,
        playhead: PlayheadClock?,
        cyclePlaybackClock: CyclePlaybackClock?,
        mutes: MuteMask?,
        handler: StepHandler,
        running: AtomicFlag
    ) {
        // Con Pattern se recorren los dieciséis; sin él, la vía del arnés. Las
        // dos construyen el mismo scheduler.
        let scheduler =
            pattern.map {
                PatternScheduler(
                    tempo: configuration.timeline.tempo, pattern: $0,
                    playbackClock: cyclePlaybackClock, mutes: mutes)
            } ?? PatternScheduler(timeline: configuration.timeline, material: material)
        let startHostTicks = HostClock.now()
        let sleepNanoseconds = UInt32(max(1_000, configuration.lookAheadNanoseconds / 2))

        // **El origen de la rejilla no es el instante de Play, sino
        // `Play + presupuesto`.** Con Delay negativo el Step 0 se pide un
        // desplazamiento por delante de su rejilla, y sin este margen ese
        // instante caería antes de que existiera el transporte. Reservarlo aquí
        // es lo que convierte un evento imposible en uno que llega justo en el
        // arranque.
        //
        // Se lee una vez, del material con el que se arranca, como se lee la
        // `MusicalTimeline`. Con Delay ≥ 0 vale cero y el origen es Play, sin
        // latencia añadida. Enmienda fechada del 2026-08-30 en `tech-stack.md`.
        let budgetNanoseconds = scheduler.advanceBudgetNanoseconds
        let gridOriginTicks =
            startHostTicks &+ HostClock.hostTicks(fromNanoseconds: UInt64(budgetNanoseconds))

        // El mismo origen que sella los timestamps es el que ve la interfaz: si
        // fueran dos, el playhead y lo que suena podrían discrepar. Se publica
        // una vez, antes del bucle, y no se vuelve a tocar mientras suene.
        playhead?.start(atHostTime: gridOriginTicks)

        while running.value {
            // El tiempo se mide contra el origen de la rejilla, que puede estar
            // por delante del arranque: durante el presupuesto, `elapsed` es
            // negativo. No es un caso especial —el horizonte sigue siendo
            // positivo por el look-ahead— y es lo que hace que el Step 0
            // adelantado se programe desde la primera vuelta.
            let elapsedNanoseconds =
                Int64(HostClock.nanoseconds(fromHostTicks: HostClock.now() &- startHostTicks))
                - budgetNanoseconds
            let horizon = elapsedNanoseconds + configuration.lookAheadNanoseconds

            scheduler.advance(toHorizon: horizon, refreshingFrom: handoff) {
                track, source, step, pitch, groove, offset in
                // El offset es relativo al origen de la rejilla, y el
                // presupuesto es lo que separa ese origen del arranque. Sumarlos
                // deja la cuenta en positivo sin más conversiones.
                //
                // **El recorte a cero es una red de seguridad, y ya solo tiene
                // un caso.** El desplazamiento nunca es más negativo que el
                // presupuesto —hay un test exhaustivo que lo fija— así que la
                // suma es positiva salvo que el Delay se baje a negativo
                // *mientras suena*: entonces el presupuesto crece y el origen ya
                // no puede acompañarlo, y una ventana de eventos se recorta una
                // sola vez. Es la limitación 2 del spec del track.
                let hostTime =
                    startHostTicks
                    &+ HostClock.hostTicks(
                        fromNanoseconds: UInt64(max(0, budgetNanoseconds + offset)))
                handler(track, source, step, pitch, groove, hostTime)
            }

            usleep(sleepNanoseconds / 1_000)
        }
    }
}
