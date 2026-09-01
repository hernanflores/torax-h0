import Engine
import Foundation

/// Parámetros de una medición de jitter.
public struct JitterMeasurementConfiguration: Sendable {

    public let tempo: Tempo
    public let division: Division

    /// Cuántos eventos se recogen antes de dar la medición por terminada.
    ///
    /// La spec del track fija 200 por defecto (~30 s a 120 BPM en 1/16). Es
    /// muestra suficiente para una desviación típica fiable, pero corta para el
    /// criterio de **máximo**: un outlier que ocurra una vez por minuto puede no
    /// aparecer. Antes de dar un resultado por definitivo conviene repetir con
    /// ~1000.
    public let sampleCount: Int

    public let lookAheadNanoseconds: Int64

    /// Tiempo máximo de espera antes de abandonar.
    public let timeoutSeconds: Double

    /// Con qué Groove medir, o `nil` para medir la rejilla recta.
    ///
    /// **`nil` no es «el Groove default», es otro camino.** Sin Groove el arnés
    /// corre en su modo `everyStep` de siempre, exactamente como antes de la
    /// rebanada 6: la medición de regresión no cambia de forma y se puede
    /// comparar contra las de las rebanadas anteriores sin asteriscos.
    ///
    /// Con Groove, el arnés mide lo que la rebanada 6 tiene que demostrar: que
    /// un instante **desplazado** se entrega donde se pidió y no donde caía la
    /// rejilla. No hace falta que el arnés sepa nada del desplazamiento —compara
    /// lo pedido contra lo entregado, y lo pedido ya lo lleva dentro—.
    public let groove: Groove?

    /// Cuántos Tracks suenan a la vez durante la medición.
    ///
    /// **Uno mide la rejilla; dieciséis miden el peor caso realista de la v2.**
    /// El coste de recorrer dieciséis rejillas dentro de la ventana no se puede
    /// deducir de la medición de una, y lo que decide si la rebanada vale es el
    /// número con las dieciséis dentro.
    public let trackCount: Int

    public init(
        tempo: Tempo,
        division: Division = .sixteenth,
        sampleCount: Int = 200,
        lookAheadNanoseconds: Int64 = 20_000_000,
        timeoutSeconds: Double = 120,
        groove: Groove? = nil,
        trackCount: Int = 1
    ) {
        self.tempo = tempo
        self.division = division
        self.sampleCount = sampleCount
        self.lookAheadNanoseconds = lookAheadNanoseconds
        self.timeoutSeconds = timeoutSeconds
        self.groove = groove
        self.trackCount = trackCount
    }
}

public enum JitterHarnessError: Error, Equatable {
    /// La medición no reunió las muestras pedidas dentro del plazo.
    case timedOut(collected: Int, expected: Int)
}

/// Resultado de medir un tempo.
public struct JitterMeasurement: Sendable {
    public let beatsPerMinute: Double
    public let statistics: JitterStatistics

    public init(beatsPerMinute: Double, statistics: JitterStatistics) {
        self.beatsPerMinute = beatsPerMinute
        self.statistics = statistics
    }
}

/// Mide la desviación real de entrega de eventos MIDI.
///
/// **Cómo funciona.** Monta el camino completo —scheduler → CoreMIDI → endpoint
/// virtual— y compara, evento a evento, el instante en que se pidió que sonara
/// con el instante en que llegó de verdad.
///
/// **Qué valida y qué no.** Valida el scheduler y la entrega de CoreMIDI. No
/// cruza el cable USB, así que la cadena hasta el sintetizador queda fuera. Y
/// medir en macOS no sustituye a medir en el iPad: son máquinas distintas con
/// planificadores distintos, y el veredicto del track exige el dispositivo.
public enum JitterHarness {

    /// Ejecuta una medición y devuelve su estadística.
    ///
    /// Bloquea el hilo llamante hasta reunir las muestras o agotar el plazo, así
    /// Measures MIDI timing jitter using the specified configuration.
    ///
    /// The measurement sends an identical note-on message for each sample, ignoring pitch and groove so that only event timing affects the result. This method must not be called from the main thread.
    /// - Parameter configuration: The tempo, rhythmic division, sample count, look-ahead interval, and timeout for the measurement.
    /// - Returns: The computed jitter statistics.
    /// - Throws: `JitterHarnessError.timedOut` if the requested samples are not collected before the timeout.
    public static func measure(
        _ configuration: JitterMeasurementConfiguration
    ) throws -> JitterStatistics {

        let recorder = JitterRecorder(capacity: configuration.sampleCount)

        let loopback = try VirtualLoopback(name: "Torax H-0 Jitter") { scheduled, actual in
            // Realtime: hilo de recepción de CoreMIDI. Resta y escritura en
            // buffer preasignado, nada más.
            let deviation =
                Int64(HostClock.nanoseconds(fromHostTicks: actual))
                - Int64(HostClock.nanoseconds(fromHostTicks: scheduled))
            recorder.record(deviation)
        }

        let output = try CoreMIDIOutput(clientName: "Torax H-0 Jitter Sender")
        let endpoint = loopback.endpoint

        let timeline = MusicalTimeline(tempo: configuration.tempo, division: configuration.division)
        let schedulerConfiguration = SchedulerConfiguration(
            timeline: timeline,
            lookAheadNanoseconds: configuration.lookAheadNanoseconds
        )

        // Nota fija: la señal de prueba es un pulso constante, no música. Lo que
        // se mide es *cuándo* llega cada evento, no qué suena.
        let message = MIDIMessage.noteOn(
            channel: MIDIChannel(unchecked: 1),
            note: MIDINote(unchecked: 60),
            velocity: MIDIVelocity(unchecked: 100)
        )

        // La altura y el Groove los ignora a propósito: el arnés mide la rejilla
        // temporal, no el material musical, y manda siempre el mismo mensaje
        // para que dos muestras solo se diferencien en cuándo salieron.
        let thread = SchedulerThread(
            configuration: schedulerConfiguration,
            material: material(for: configuration.groove),
            pattern: pattern(forTrackCount: configuration.trackCount, groove: configuration.groove)
        ) {
            _, _, _, _, hostTime in
            // Realtime: hilo del scheduler.
            output.send(message, to: endpoint, atHostTime: hostTime)
        }

        thread.start()
        defer { thread.stop() }

        let deadline = Date().addingTimeInterval(configuration.timeoutSeconds)
        while !recorder.isFull && Date() < deadline {
            usleep(2_000)
        }

        guard recorder.isFull else {
            throw JitterHarnessError.timedOut(
                collected: recorder.sampleCount,
                expected: configuration.sampleCount
            )
        }

        return recorder.statistics()
    }

    /// Con qué material corre el scheduler durante la medición.
    ///
    /// **Sin Groove, el modo `everyStep` de siempre.** Es el mismo camino que
    /// las mediciones anteriores a la rebanada 6, así que la referencia contra
    /// la que se compara una regresión no cambia de forma.
    ///
    /// **Con Groove, un anillo lleno.** Todos los Steps disparan —Pulses igual a
    /// Steps— y el pool lleva una sola altura, así que sigue sonando en todos los
    /// Steps y sigue mandando el mismo mensaje: lo único que cambia respecto a
    /// `everyStep` es que ahora los instantes llevan el desplazamiento dentro.
    /// Un reparto euclidiano de verdad solo quitaría muestras al histograma.
    /// Los Tracks que suenan durante la medición, o `nil` para medir con uno.
    ///
    /// Todos llevan el anillo lleno y la misma altura: el arnés manda un mensaje
    /// fijo y lo que mide es *cuándo* sale, no qué suena. Con dieciséis, cada
    /// Step entrega dieciséis mensajes con el mismo instante programado, que es
    /// exactamente la carga que la v2 introduce.
    static func pattern(forTrackCount count: Int, groove: Groove?) -> Pattern? {
        guard count > 1 else { return nil }

        guard let steps = Steps(16), let pulses = Pulses(16), let pitch = Pitch(60) else {
            return nil
        }

        var pattern = Pattern()
        for index in 0..<min(count, Pattern.trackCount) {
            pattern = pattern.replacing(
                Track(
                    shape: Shape(steps: steps, pulses: pulses),
                    pool: PitchPool().inserting(pitch),
                    groove: groove ?? .default
                ),
                at: index
            )
        }
        return pattern
    }

    static func material(for groove: Groove?) -> SchedulerMaterial {
        // El anillo lleno se construye con los inicializadores validadores, que
        // es lo que `code_styleguides/swift.md` pide fuera de los tests. Sus
        // valores están dentro de rango, así que la rama de escape no se toma
        // nunca; existe para no forzar un desempaquetado.
        guard let groove, let steps = Steps(16), let pulses = Pulses(16) else {
            return .everyStep
        }

        return .track(
            Track(
                shape: Shape(steps: steps, pulses: pulses),
                pool: PitchPool().toggling(SchedulerMaterial.measurementPitch),
                groove: groove
            )
        )
    }

    /// Recorre varios tempos y devuelve la medición de cada uno.
    ///
    /// El barrido existe para revelar si el error escala con el tempo: un fallo
    /// que solo aparece a 174 BPM no se ve midiendo únicamente a 120.
    public static func sweep(
        tempos: [Double] = [60, 120, 174],
        sampleCount: Int = 200,
        lookAheadNanoseconds: Int64 = 20_000_000,
        timeoutSeconds: Double = 120,
        groove: Groove? = nil
    ) throws -> [JitterMeasurement] {
        try tempos.compactMap { beatsPerMinute in
            guard let tempo = Tempo(beatsPerMinute: beatsPerMinute) else { return nil }
            let statistics = try measure(
                JitterMeasurementConfiguration(
                    tempo: tempo,
                    sampleCount: sampleCount,
                    lookAheadNanoseconds: lookAheadNanoseconds,
                    timeoutSeconds: timeoutSeconds,
                    groove: groove
                )
            )
            return JitterMeasurement(beatsPerMinute: beatsPerMinute, statistics: statistics)
        }
    }
}
