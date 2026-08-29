import Foundation

/// Resumen estadístico de las desviaciones de entrega, en nanosegundos.
///
/// Convierte el criterio de éxito del track —"timing MIDI estable"— en tres
/// números que se pueden contrastar contra un umbral.
public struct JitterStatistics: Equatable, Sendable {

    /// Umbral de aceptación del track `timing-spike_20260826`.
    public static let maximumThresholdNanoseconds: Int64 = 2_000_000  // 2 ms
    public static let standardDeviationThresholdNanoseconds: Double = 500_000  // 0,5 ms

    public let sampleCount: Int

    /// Mayor desviación en **valor absoluto**.
    ///
    /// Llegar pronto es tan malo como llegar tarde: un criterio que solo mirara
    /// los retrasos dejaría pasar un adelanto grave.
    public let maximumAbsoluteNanoseconds: Int64

    /// Desviación media, **con signo**.
    ///
    /// Conserva el signo a propósito: un sesgo constante —todo llega 2 ms
    /// tarde— es un problema distinto del jitter, y se corrige de otra manera.
    /// Confundirlos llevaría a buscar el fallo donde no está.
    public let meanNanoseconds: Double

    /// Desviación típica **poblacional** (divide por N, no por N−1).
    ///
    /// Las muestras no son un subconjunto de una población mayor: son todos los
    /// eventos de la medición.
    public let standardDeviationNanoseconds: Double

    public init(deviationsNanoseconds deviations: [Int64]) {
        sampleCount = deviations.count

        guard !deviations.isEmpty else {
            maximumAbsoluteNanoseconds = 0
            meanNanoseconds = 0
            standardDeviationNanoseconds = 0
            return
        }

        maximumAbsoluteNanoseconds = deviations.map(abs).max() ?? 0

        let mean = deviations.reduce(0.0) { $0 + Double($1) } / Double(deviations.count)
        meanNanoseconds = mean

        let variance =
            deviations.reduce(0.0) { partial, value in
                let delta = Double(value) - mean
                return partial + delta * delta
            } / Double(deviations.count)
        standardDeviationNanoseconds = variance.squareRoot()
    }

    /// Indica si la medición cumple el umbral de aceptación del track.
    public var meetsTrackThreshold: Bool {
        maximumAbsoluteNanoseconds < Self.maximumThresholdNanoseconds
            && standardDeviationNanoseconds < Self.standardDeviationThresholdNanoseconds
    }

    /// Resumen legible, en milisegundos.
    public var summary: String {
        let maximum = Double(maximumAbsoluteNanoseconds) / 1_000_000
        let mean = meanNanoseconds / 1_000_000
        let deviation = standardDeviationNanoseconds / 1_000_000
        let verdict = meetsTrackThreshold ? "CUMPLE" : "NO CUMPLE"
        return String(
            format: "n=%d  máx=%.3f ms  media=%+.3f ms  σ=%.3f ms  → %@",
            sampleCount, maximum, mean, deviation, verdict
        )
    }
}

/// Recoge desviaciones desde el hilo de tiempo real de CoreMIDI.
///
/// **Buffer preasignado.** Grabar una muestra no puede asignar memoria: el
/// registro ocurre dentro del bloque de recepción de CoreMIDI, donde una
/// asignación introduciría justo el jitter que se está intentando medir. Al
/// llenarse, descarta en vez de crecer.
///
/// **Un solo productor.** Está pensado para el hilo de recepción de CoreMIDI,
/// que es único. La lectura (`deviations()`, `statistics()`) se hace desde otro
/// hilo cuando la medición ya ha terminado.
public final class JitterRecorder: @unchecked Sendable {

    private let storage: UnsafeMutablePointer<Int64>
    private let capacity: Int
    private let recorded = AtomicCounter()

    public init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    public var sampleCount: Int { Int(recorded.value) }

    /// ¿Se ha alcanzado la capacidad?
    public var isFull: Bool { sampleCount >= capacity }

    /// Registra una desviación.
    ///
    /// Realtime: llamado desde el hilo de recepción de CoreMIDI.
    /// Sin asignaciones, sin locks, sin await.
    public func record(_ deviationNanoseconds: Int64) {
        let index = Int(recorded.value)
        guard index < capacity else { return }
        storage[index] = deviationNanoseconds
        recorded.increment()
    }

    /// Copia de las muestras registradas. No es código de tiempo real.
    public func deviations() -> [Int64] {
        Array(UnsafeBufferPointer(start: storage, count: sampleCount))
    }

    public func statistics() -> JitterStatistics {
        JitterStatistics(deviationsNanoseconds: deviations())
    }
}
