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

    public init(
        tempo: Tempo,
        division: Division = .sixteenth,
        sampleCount: Int = 200,
        lookAheadNanoseconds: Int64 = 20_000_000,
        timeoutSeconds: Double = 120
    ) {
        self.tempo = tempo
        self.division = division
        self.sampleCount = sampleCount
        self.lookAheadNanoseconds = lookAheadNanoseconds
        self.timeoutSeconds = timeoutSeconds
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
    /// que no debe invocarse desde el hilo principal.
    public static func measure(
        _ configuration: JitterMeasurementConfiguration
    ) throws -> JitterStatistics {

        let recorder = JitterRecorder(capacity: configuration.sampleCount)

        let loopback = try VirtualLoopback(name: "Torax H-0 Jitter") { scheduled, actual in
            // Realtime: hilo de recepción de CoreMIDI. Resta y escritura en
            // buffer preasignado, nada más.
            let deviation = Int64(HostClock.nanoseconds(fromHostTicks: actual))
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

        let thread = SchedulerThread(configuration: schedulerConfiguration) { _, hostTime in
            // Realtime: hilo del scheduler.
            output.send(message, to: endpoint, atHostTime: hostTime)
        }

        thread.start()

        // Desmontaje explícito y en orden, en lugar de confiar en `defer` para
        // el hilo y en ARC para el resto.
        //
        // El orden lo impone el problema, no el gusto: destruir los recursos de
        // CoreMIDI mientras todavía está emitiendo eventos ya sellados con
        // timestamp futuro inutiliza la conexión MIDI del proceso, y las
        // siguientes llamadas a `MIDIClientCreateWithBlock` devuelven
        // `paramErr`. Ver el track `scheduler-lifecycle_20260826`.
        //
        //   1. dejar de programar eventos nuevos
        //   2. dejar que se vacíe la ventana ya entregada
        //   3. dejar de enviar  (puerto y cliente del emisor)
        //   4. destruir endpoint y cliente del loopback
        //
        // El paso 2 es el que antes no existía: sin él, los pasos 3 y 4 caen
        // dentro de la ventana. Se espera el doble del look-ahead, que acota por
        // arriba lo que CoreMIDI pueda tener pendiente.
        defer {
            thread.stop()
            usleep(UInt32(configuration.lookAheadNanoseconds * 2 / 1_000))
            output.close()
            loopback.close()
        }

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

    /// Recorre varios tempos y devuelve la medición de cada uno.
    ///
    /// El barrido existe para revelar si el error escala con el tempo: un fallo
    /// que solo aparece a 174 BPM no se ve midiendo únicamente a 120.
    public static func sweep(
        tempos: [Double] = [60, 120, 174],
        sampleCount: Int = 200,
        lookAheadNanoseconds: Int64 = 20_000_000,
        timeoutSeconds: Double = 120
    ) throws -> [JitterMeasurement] {
        try tempos.compactMap { beatsPerMinute in
            guard let tempo = Tempo(beatsPerMinute: beatsPerMinute) else { return nil }
            let statistics = try measure(
                JitterMeasurementConfiguration(
                    tempo: tempo,
                    sampleCount: sampleCount,
                    lookAheadNanoseconds: lookAheadNanoseconds,
                    timeoutSeconds: timeoutSeconds
                )
            )
            return JitterMeasurement(beatsPerMinute: beatsPerMinute, statistics: statistics)
        }
    }
}
