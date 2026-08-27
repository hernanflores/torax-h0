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
/// `TrackHandoff`, que el hilo consulta una vez por ventana. Esto sigue siendo
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
    /// Recibe el índice de Step y el instante de emisión en ticks de host.
    /// Quien lo implemente hereda las reglas de tiempo real: sin asignaciones,
    /// sin locks, sin logging.
    public typealias StepHandler = @Sendable (_ step: Int, _ hostTime: UInt64) -> Void

    private let configuration: SchedulerConfiguration
    private let track: Track?
    private let handoff: TrackHandoff?
    private let handler: StepHandler
    private let running = AtomicFlag(false)
    private var thread: Thread?

    /// - Parameters:
    ///   - track: Track con el que arranca. `nil` emite todos los Steps, que es
    ///     lo que quiere el arnés de medición.
    ///   - handoff: por donde llegan los Tracks publicados mientras suena. `nil`
    ///     deja el Track fijo durante toda la reproducción.
    public init(
        configuration: SchedulerConfiguration,
        track: Track? = nil,
        handoff: TrackHandoff? = nil,
        handler: @escaping StepHandler
    ) {
        self.configuration = configuration
        self.track = track
        self.handoff = handoff
        self.handler = handler
    }

    public var isRunning: Bool { running.value }

    public func start() {
        guard !running.value else { return }
        running.value = true

        let thread = Thread { [configuration, track, handoff, handler, running] in
            SchedulerThread.run(
                configuration: configuration,
                track: track,
                handoff: handoff,
                handler: handler,
                running: running
            )
        }
        thread.name = "com.toraxh0.scheduler"
        // Prioridad máxima: el hilo compite con la interfaz por la CPU y el
        // retraso aquí se traduce en eventos perdidos al borde de la ventana.
        thread.qualityOfService = .userInteractive
        thread.threadPriority = 1.0
        self.thread = thread
        thread.start()
    }

    public func stop() {
        running.value = false
        thread = nil
    }

    /// Bucle del scheduler.
    ///
    /// Realtime: este es el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private static func run(
        configuration: SchedulerConfiguration,
        track: Track?,
        handoff: TrackHandoff?,
        handler: StepHandler,
        running: AtomicFlag
    ) {
        var scheduler = TrackScheduler(timeline: configuration.timeline, track: track)
        let startHostTicks = HostClock.now()
        let sleepNanoseconds = UInt32(max(1_000, configuration.lookAheadNanoseconds / 2))

        while running.value {
            let elapsedNanoseconds = Int64(
                HostClock.nanoseconds(fromHostTicks: HostClock.now() &- startHostTicks)
            )
            let horizon = elapsedNanoseconds + configuration.lookAheadNanoseconds

            scheduler.advance(toHorizon: horizon, refreshingFrom: handoff) { step, offset in
                let hostTime = startHostTicks
                    &+ HostClock.hostTicks(fromNanoseconds: UInt64(max(0, offset)))
                handler(step, hostTime)
            }

            usleep(sleepNanoseconds / 1_000)
        }
    }
}
