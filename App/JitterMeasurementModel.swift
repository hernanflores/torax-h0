import Engine
import Foundation
import MIDI
import Observation
import UIKit

/// Estado de la pantalla de medición.
///
/// Instrumentación del track `timing-spike_20260826`, no producto: su única
/// función es lanzar el barrido en el iPad y mostrar los números.
@MainActor
@Observable
final class JitterMeasurementModel {

    /// Tamaños de muestra de la spec: 200 para la medición normal, 1000 para la
    /// pasada larga que cubre la limitación de muestra corta.
    static let sampleCountOptions = [200, 1_000]
    static let tempos: [Double] = [60, 120, 174]

    /// Con qué rejilla medir.
    ///
    /// **Instrumentación de la rebanada 6, no producto.** La medición recta es
    /// la de siempre —la que se compara contra la referencia de la rebanada 3—;
    /// las otras tres son lo que la rebanada tiene que demostrar: que un
    /// instante desplazado se entrega donde se pidió.
    ///
    /// Los cuatro casos son exactamente los que pide el plan del track. No hay
    /// un selector libre de Timing y Delay porque medir no es tocar: lo que hace
    /// falta es repetir siempre los mismos cuatro y poder compararlos entre
    /// pasadas.
    enum Grid: String, CaseIterable, Identifiable {
        case straight = "Recta"
        case swung = "Timing 67%"
        case dragged = "Delay +50%"
        case pushed = "Delay −50%"

        /// **El peor caso realista de la v2**: todos los Tracks sonando a la
        /// vez. Es lo que decide si la rebanada de múltiples Tracks vale, y no
        /// se puede deducir de la medición de uno.
        ///
        /// > **Eran dieciséis y son doce desde el 2026-09-02.** La rejilla pide
        /// > `Pattern.trackCount` Tracks, así que una app de doce ya no puede
        /// > construir la de dieciséis y la herramienta se quedaría rota
        /// > esperando a que alguien la corriera. **No se mide**: las mediciones
        /// > de jitter están suspendidas y esto solo deja el arnés coherente por
        /// > si se retoman.
        case everyTrack = "12 Tracks"
        case everyTrackWithCycles = "12 Tracks · 4 Cycles"

        var id: String { rawValue }

        /// Sufijo del fichero de informe. Sin acentos ni espacios, para que el
        /// nombre sobreviva a cualquier forma de sacarlo del dispositivo.
        var fileNameSuffix: String {
            switch self {
            case .straight: "recta"
            case .swung: "timing-67"
            case .dragged: "delay-mas-50"
            case .pushed: "delay-menos-50"
            case .everyTrack: "12-tracks"
            case .everyTrackWithCycles: "12-tracks-cycles"
            }
        }

        /// El Groove con el que medir, o `nil` en la recta — que no es «el
        /// Groove default» sino el modo `everyStep` del arnés, el mismo camino
        /// que recorrieron las mediciones anteriores a la rebanada 6.
        /// Cuántos Tracks suenan durante la medición.
        var trackCount: Int {
            switch self {
            case .everyTrack, .everyTrackWithCycles: Pattern.trackCount
            default: 1
            }
        }

        /// Cuántos Cycles recorre cada Track.
        ///
        /// **Cuatro y no dieciséis**: lo que se mide es el coste de *avanzar*,
        /// que ocurre una vez por vuelta y no depende de cuántos haya; con
        /// cuatro, una pasada completa cabe en la medición varias veces y el
        /// cambio de material se ejerce de sobra. Dieciséis solo alargarían la
        /// pasada sin ejercer nada nuevo.
        var cycleCount: Int {
            switch self {
            case .everyTrackWithCycles: 4
            default: 1
            }
        }

        var groove: Groove? {
            switch self {
            case .straight:
                return nil
            case .swung:
                return groove(timing: 67, delay: 0)
            case .dragged:
                return groove(timing: 50, delay: 50)
            case .pushed:
                return groove(timing: 50, delay: -50)
            case .everyTrack, .everyTrackWithCycles:
                // Recta, para que lo único que cambie respecto a la referencia
                // sean los Tracks y sus Cycles, y no el Groove.
                return nil
            }
        }

        private func groove(timing: Int, delay: Int) -> Groove? {
            guard let timing = Timing(percent: timing), let delay = Delay(percent: delay) else {
                return nil
            }
            return Groove(
                velocity: .default,
                sustain: .default,
                probability: .default,
                timing: timing,
                delay: delay
            )
        }
    }

    private(set) var isRunning = false
    private(set) var statusMessage = "Listo para medir"
    private(set) var measurements: [JitterMeasurement] = []
    private(set) var failureMessage: String?

    var sampleCount = 200
    var grid: Grid = .straight

    private var task: Task<Void, Never>?

    /// Veredicto global: solo cumple si lo cumplen todos los tempos medidos.
    var overallVerdict: Bool? {
        guard measurements.count == Self.tempos.count else { return nil }
        return measurements.allSatisfy(\.statistics.meetsTrackThreshold)
    }

    /// Starts a jitter measurement for each configured tempo and updates the measurement state.
    /// The measurement disables automatic screen locking while running and saves a report when it completes or fails.
    func start() {
        guard !isRunning else { return }

        isRunning = true
        measurements = []
        failureMessage = nil

        // Una pasada larga (1000 eventos por tempo) dura unos 8 minutos. Si el
        // iPad se auto-bloqueara a mitad, la app se suspende y la medicion
        // queda corrupta — con la particularidad de que el resultado parcial
        // parecería válido.
        UIApplication.shared.isIdleTimerDisabled = true

        let sampleCount = sampleCount
        let groove = grid.groove
        let trackCount = grid.trackCount
        let cycleCount = grid.cycleCount
        task = Task { [weak self] in
            for beatsPerMinute in Self.tempos {
                if Task.isCancelled { break }
                self?.statusMessage =
                    "Midiendo \(Int(beatsPerMinute)) BPM · \(sampleCount) eventos…"

                // La medición bloquea su hilo mientras espera los eventos, así
                // que corre fuera del hilo principal: si lo bloqueara, la propia
                // interfaz competiría con el scheduler y falsearía el resultado.
                self?.writeTrace("inicio \(Int(beatsPerMinute)) BPM")
                let trace: @Sendable (String) -> Void = { [weak self] in self?.writeTrace($0) }
                let outcome = await Task.detached(priority: .userInitiated) {
                    JitterMeasurementModel.measure(
                        beatsPerMinute: beatsPerMinute, sampleCount: sampleCount,
                        groove: groove, trackCount: trackCount, cycleCount: cycleCount,
                        trace: trace
                    )
                }.value
                self?.writeTrace("fin \(Int(beatsPerMinute)) BPM")

                guard let self else { return }
                switch outcome {
                case .success(let measurement):
                    self.measurements.append(measurement)
                    // A stdout para poder capturar la medicion desde
                    // `devicectl ... --console` sin depender de la pantalla.
                    print(
                        "[jitter] \(Int(measurement.beatsPerMinute)) BPM · \(measurement.statistics.summary)"
                    )
                case .failure(let message):
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.failureMessage = message
                    self.statusMessage = "Medición interrumpida"
                    self.isRunning = false
                    // El informe se escribe TAMBIEN al fallar: un fallo sin
                    // rastro no se puede diagnosticar.
                    self.writeReport()
                    return
                }
            }

            guard let self else { return }
            UIApplication.shared.isIdleTimerDisabled = false
            self.statusMessage = Task.isCancelled ? "Detenido" : "Medición completa"
            self.isRunning = false
            if let verdict = self.overallVerdict {
                print("[jitter] VEREDICTO: \(verdict ? "CUMPLE" : "NO CUMPLE")")
            }
            self.writeReport()
        }
    }

    /// Arranca automáticamente si se lanzó con `--auto-measure`.
    ///
    /// Existe para que la medición sea reproducible desde línea de comandos
    /// (`devicectl ... --console`) y no dependa de que alguien pulse un botón:
    /// el arnés de jitter es una herramienta permanente según `workflow.md`, no
    /// un experimento de una sola vez.
    ///
    /// Starts a measurement automatically when the `--auto-measure` launch argument is present.
    /// - Parameter: Launch arguments may include `--samples=<n>` to set a positive sample count before measurement begins.
    func startIfRequestedByLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--auto-measure") else { return }

        if let raw = arguments.first(where: { $0.hasPrefix("--samples=") }),
            let parsed = Int(raw.dropFirst("--samples=".count)), parsed > 0
        {
            sampleCount = parsed
        }

        // **La rejilla también, desde que el arnés dejó de tener pantalla**
        // (FR12 de la rebanada 2 de la v2). Era lo único que solo se podía
        // elegir tocando, así que quitar la UI sin esto habría dejado el arnés
        // midiendo siempre la recta — y las otras cuatro rejillas existen
        // precisamente para lo que no se puede deducir de ella.
        if let raw = arguments.first(where: { $0.hasPrefix("--grid=") }) {
            let name = String(raw.dropFirst("--grid=".count))
            if let chosen = Grid.allCases.first(where: { $0.fileNameSuffix == name }) {
                grid = chosen
            } else {
                let names = Grid.allCases.map(\.fileNameSuffix).joined(separator: ", ")
                print("[jitter] rejilla desconocida '\(name)'. Válidas: \(names)")
            }
        }

        print("[jitter] arranque automático · \(sampleCount) eventos por tempo · \(grid.rawValue)")
        writeTrace("arranque automático · \(sampleCount) eventos por tempo · \(grid.rawValue)")
        start()
    }

    func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        task?.cancel()
        task = nil
        isRunning = false
        statusMessage = "Detenido"
    }

    /// `nonisolated` a propósito: corre en un hilo de fondo, no en el
    /// principal. Si la medición bloqueara el hilo de la interfaz, la propia UI
    /// competiría con el scheduler y falsearía justo lo que se mide.
    /// Traza de progreso a `Documents/jitter-trace.txt`.
    ///
    /// Se escribe en cada hito para poder reconstruir hasta dónde llegó la
    /// Appends a timestamped line to the jitter trace file in the Documents directory.
    /// - Parameter line: The trace message to record.
    nonisolated func writeTrace(_ line: String) {
        guard
            let directory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else { return }
        let url = directory.appendingPathComponent("jitter-trace.txt")
        let stamped = "\(Date()) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? stamped.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Escribe el informe a `Documents/jitter-report-<rejilla>.txt`.
    ///
    /// El streaming de consola (`devicectl --console`) se invalida en
    /// mediciones de varios minutos, así que el resultado se persiste en el
    /// dispositivo y se recoge después. La medición sobrevive a cualquier corte
    /// Writes a jitter measurement report to the device's Documents directory.
    private func writeReport() {
        guard
            let directory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else { return }

        var lines: [String] = []
        lines.append("Torax H-0 — timing spike")
        lines.append(
            "dispositivo: \(UIDevice.current.model) · iPadOS \(UIDevice.current.systemVersion)")
        lines.append("eventos por tempo: \(sampleCount)")
        lines.append("rejilla: \(grid.rawValue)")
        lines.append("umbral: máx < 2 ms · σ < 0,5 ms")
        lines.append("")
        for measurement in measurements {
            lines.append(
                "\(Int(measurement.beatsPerMinute)) BPM · \(measurement.statistics.summary)")
        }
        lines.append("")
        if let verdict = overallVerdict {
            lines.append("VEREDICTO: \(verdict ? "CUMPLE" : "NO CUMPLE")")
        } else {
            lines.append(
                "VEREDICTO: incompleto (\(measurements.count) de \(Self.tempos.count) tempos)")
        }
        if let failure = failureMessage { lines.append("fallo: \(failure)") }

        // **Un fichero por rejilla.** La rebanada 6 mide cuatro veces —recta,
        // swing y los dos Delay— y un nombre fijo dejaría solo la última: la
        // medición de regresión, que es la que hay que comparar contra la
        // referencia, la habría pisado cualquiera de las otras tres.
        let url = directory.appendingPathComponent("jitter-report-\(grid.fileNameSuffix).txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("[jitter] informe escrito en \(url.path)")
    }

    private enum Outcome: Sendable {
        case success(JitterMeasurement)
        case failure(String)
    }

    /// Performs a jitter measurement for the specified tempo and sample count.
    /// - Parameters:
    ///   - beatsPerMinute: The tempo to measure, in beats per minute.
    ///   - sampleCount: The number of events to collect.
    /// - Returns: A successful measurement or a failure describing an invalid tempo, timeout, or measurement error.
    private nonisolated static func measure(
        beatsPerMinute: Double, sampleCount: Int, groove: Groove? = nil, trackCount: Int = 1,
        cycleCount: Int = 1, trace: @Sendable (String) -> Void = { _ in }
    ) -> Outcome {
        guard let tempo = Tempo(beatsPerMinute: beatsPerMinute) else {
            return .failure("Tempo fuera de rango: \(beatsPerMinute) BPM")
        }
        do {
            trace("llamando a JitterHarness.measure \(Int(beatsPerMinute)) BPM")
            let statistics = try JitterHarness.measure(
                JitterMeasurementConfiguration(
                    tempo: tempo,
                    sampleCount: sampleCount,
                    timeoutSeconds: 300,
                    groove: groove,
                    trackCount: trackCount,
                    cycleCount: cycleCount
                )
            )
            return .success(
                JitterMeasurement(beatsPerMinute: beatsPerMinute, statistics: statistics))
        } catch let JitterHarnessError.timedOut(collected, expected) {
            return .failure(
                "Tiempo agotado a \(Int(beatsPerMinute)) BPM: \(collected) de \(expected) eventos")
        } catch {
            return .failure("Fallo a \(Int(beatsPerMinute)) BPM: \(error)")
        }
    }
}
