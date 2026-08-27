import Engine
import Foundation
import MIDI
import Observation

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

    private(set) var isRunning = false
    private(set) var statusMessage = "Listo para medir"
    private(set) var measurements: [JitterMeasurement] = []
    private(set) var failureMessage: String?

    var sampleCount = 200

    private var task: Task<Void, Never>?

    /// Veredicto global: solo cumple si lo cumplen todos los tempos medidos.
    var overallVerdict: Bool? {
        guard measurements.count == Self.tempos.count else { return nil }
        return measurements.allSatisfy(\.statistics.meetsTrackThreshold)
    }

    func start() {
        guard !isRunning else { return }

        isRunning = true
        measurements = []
        failureMessage = nil

        let sampleCount = sampleCount
        task = Task { [weak self] in
            for beatsPerMinute in Self.tempos {
                if Task.isCancelled { break }
                self?.statusMessage = "Midiendo \(Int(beatsPerMinute)) BPM · \(sampleCount) eventos…"

                // La medición bloquea su hilo mientras espera los eventos, así
                // que corre fuera del hilo principal: si lo bloqueara, la propia
                // interfaz competiría con el scheduler y falsearía el resultado.
                let outcome = await Task.detached(priority: .userInitiated) {
                    JitterMeasurementModel.measure(beatsPerMinute: beatsPerMinute, sampleCount: sampleCount)
                }.value

                guard let self else { return }
                switch outcome {
                case let .success(measurement):
                    self.measurements.append(measurement)
                case let .failure(message):
                    self.failureMessage = message
                    self.statusMessage = "Medición interrumpida"
                    self.isRunning = false
                    return
                }
            }

            guard let self else { return }
            self.statusMessage = Task.isCancelled ? "Detenido" : "Medición completa"
            self.isRunning = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        statusMessage = "Detenido"
    }

    /// `nonisolated` a propósito: corre en un hilo de fondo, no en el
    /// principal. Si la medición bloqueara el hilo de la interfaz, la propia UI
    /// competiría con el scheduler y falsearía justo lo que se mide.
    private enum Outcome: Sendable {
        case success(JitterMeasurement)
        case failure(String)
    }

    private nonisolated static func measure(beatsPerMinute: Double, sampleCount: Int) -> Outcome {
        guard let tempo = Tempo(beatsPerMinute: beatsPerMinute) else {
            return .failure("Tempo fuera de rango: \(beatsPerMinute) BPM")
        }
        do {
            let statistics = try JitterHarness.measure(
                JitterMeasurementConfiguration(
                    tempo: tempo,
                    sampleCount: sampleCount,
                    timeoutSeconds: 300
                )
            )
            return .success(JitterMeasurement(beatsPerMinute: beatsPerMinute, statistics: statistics))
        } catch let JitterHarnessError.timedOut(collected, expected) {
            return .failure("Tiempo agotado a \(Int(beatsPerMinute)) BPM: \(collected) de \(expected) eventos")
        } catch {
            return .failure("Fallo a \(Int(beatsPerMinute)) BPM: \(error)")
        }
    }
}
