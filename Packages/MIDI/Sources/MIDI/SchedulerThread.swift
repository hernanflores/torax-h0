import Darwin
import Engine
import Foundation

/// Snapshot inmutable de la configuración con la que corre el scheduler.
///
/// El hilo del scheduler captura este valor al arrancar y no vuelve a leer
/// estado compartido: no hay lock que tomar porque no hay nada mutable que
/// proteger. Cambiar parámetros en caliente —girar un knob mientras suena—
/// exigirá publicar un snapshot nuevo de forma atómica; eso llega con el
/// producto, no con el spike.
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
/// Resultado de pedir que el scheduler pare.
public enum SchedulerStopResult: Equatable, Sendable {
    /// El hilo salió del bucle antes de agotar la cota. Es el caso normal:
    /// tarda lo que el bucle en despertar, del orden de milisegundos.
    case stopped
    /// Se agotó la cota sin ver salir al hilo.
    ///
    /// **Se reporta, no se cuelga a quien pide parar.** Si esto ocurre el hilo
    /// sigue vivo, y arrancar otro solaparía bucles: quien lo reciba no debe
    /// volver a arrancar sin más.
    case timedOut
}

public final class SchedulerThread: @unchecked Sendable {

    /// Se invoca por cada Step, desde el hilo del scheduler.
    ///
    /// Recibe el índice de Step y el instante de emisión en ticks de host.
    /// Quien lo implemente hereda las reglas de tiempo real: sin asignaciones,
    /// sin locks, sin logging.
    public typealias StepHandler = @Sendable (_ step: Int, _ hostTime: UInt64) -> Void

    private let configuration: SchedulerConfiguration
    private let handler: StepHandler
    private let running = AtomicFlag(false)

    /// Baja mientras hay un bucle vivo; sube cuando sale.
    ///
    /// Es la señal que hace que `stop()` signifique parar. La bandera `running`
    /// sola no basta: es una PETICIÓN de parada, y entre bajarla y que el hilo
    /// la lea pasa hasta media ventana, porque está dormido. Sin una señal de
    /// salida, un `start()` dentro de esa ventana vuelve a subir `running` y el
    /// hilo viejo nunca llega a leer el `false` — quedan dos bucles emitiendo
    /// cada Step dos veces.
    private let finished = AtomicFlag(true)

    private var thread: Thread?

    /// Cuánto espera `stop()` como máximo a que el hilo salga.
    ///
    /// El bucle duerme media ventana, así que sale en ese orden de magnitud. Un
    /// segundo es holgadísimo a propósito: la cota existe para que parar no
    /// pueda colgarse nunca, no para apretar el caso normal.
    private static let stopTimeoutNanoseconds: UInt64 = 1_000_000_000

    public init(configuration: SchedulerConfiguration, handler: @escaping StepHandler) {
        self.configuration = configuration
        self.handler = handler
    }

    public var isRunning: Bool { running.value }

    public func start() {
        guard !running.value else { return }
        running.value = true
        finished.value = false

        let thread = Thread { [configuration, handler, running, finished] in
            SchedulerThread.run(configuration: configuration, handler: handler, running: running)
            // Señal de salida: es lo que `stop()` espera. Va aquí, fuera del
            // bucle, para que suba exactamente cuando ya no puede emitirse nada.
            finished.value = true
        }
        thread.name = "com.toraxh0.scheduler"
        // Prioridad máxima: el hilo compite con la interfaz por la CPU y el
        // retraso aquí se traduce en eventos perdidos al borde de la ventana.
        thread.qualityOfService = .userInteractive
        thread.threadPriority = 1.0
        self.thread = thread
        thread.start()
    }

    /// Pide parar y **espera a que el hilo salga del bucle**.
    ///
    /// Cuando esto retorna `.stopped`, el handler no volverá a invocarse: ni un
    /// Step más. Es lo que permite que un `start()` inmediatamente después
    /// arranque exactamente un scheduler y no dos.
    ///
    /// **La espera corre en el hilo de control, nunca en el del scheduler.**
    /// Llamar a `stop()` desde dentro del bucle sería un error de programación,
    /// no un caso a soportar: se esperaría a sí mismo hasta agotar la cota.
    ///
    /// Bloquea del orden de milisegundos —lo que tarda el bucle en despertar—,
    /// que para un gesto de transporte está por debajo de un fotograma.
    @discardableResult
    public func stop() -> SchedulerStopResult {
        running.value = false
        thread = nil

        let deadline = HostClock.now()
            &+ HostClock.hostTicks(fromNanoseconds: Self.stopTimeoutNanoseconds)
        while !finished.value && HostClock.now() < deadline {
            usleep(200)
        }

        return finished.value ? .stopped : .timedOut
    }

    /// Bucle del scheduler.
    ///
    /// Realtime: este es el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private static func run(
        configuration: SchedulerConfiguration,
        handler: StepHandler,
        running: AtomicFlag
    ) {
        var scheduler = LookAheadScheduler(timeline: configuration.timeline)
        let startHostTicks = HostClock.now()
        let sleepNanoseconds = UInt32(max(1_000, configuration.lookAheadNanoseconds / 2))

        while running.value {
            let elapsedNanoseconds = Int64(
                HostClock.nanoseconds(fromHostTicks: HostClock.now() &- startHostTicks)
            )
            let horizon = elapsedNanoseconds + configuration.lookAheadNanoseconds

            for step in scheduler.advance(toHorizon: horizon) {
                let offset = configuration.timeline.nanosecondOffset(forStep: step)
                let hostTime = startHostTicks
                    &+ HostClock.hostTicks(fromNanoseconds: UInt64(max(0, offset)))
                handler(step, hostTime)
            }

            usleep(sleepNanoseconds / 1_000)
        }
    }
}
