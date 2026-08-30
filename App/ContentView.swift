import CoreMIDI
import Engine
import MIDI
import SwiftUI

/// La pantalla del Track.
///
/// **El controlador es el instrumento; la pantalla es el espejo**
/// (`product-guidelines.md`). Nada de lo que hay aquí se edita tocando: el
/// anillo, el playhead y el valor grande informan, y los parámetros
/// generativos se mueven con knobs. Lo táctil se limita a lo que la guía
/// asigna a la pantalla — transporte y selección de dispositivo.
///
/// **Sin controlador conectado la app es de solo lectura y transporte.** El
/// anillo y el playhead siguen viéndose, porque son estado y no edición; lo que
/// no aparece es el valor grande, porque nadie gira nada. No se abre ninguna
/// vía táctil para suplirlo: un slider provisional para Steps o Pulses sería el
/// antipatrón que la guía nombra.
///
/// El panel de medición de jitter sigue debajo porque la Fase 4 del track exige
/// medir con la interfaz corriendo: el anillo redibujándose es justamente la
/// carga visual que faltaba por medir.
struct ContentView: View {

    @State private var model = TransportModel()
    @State private var jitter = JitterMeasurementModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                pattern
                transport
                Divider().overlay(Palette.border)
                TonalView(
                    frame: model.frame,
                    pool: model.track.pool,
                    onFrameChange: { model.setFrame($0) }
                )
                Divider().overlay(Palette.border)
                measurement
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background)
        .foregroundStyle(.white)
        .onAppear { jitter.startIfRequestedByLaunchArguments() }
    }

    // MARK: - El patrón

    /// El anillo, con el valor grande encima cuando lo hay.
    ///
    /// **El anillo nunca se oculta.** `product-guidelines.md`: el valor
    /// transitorio se dibuja *sobre* el patrón, que permanece siempre visible
    /// bajo él. Nunca se sustituye el contexto por el detalle, así que esto es
    /// un `ZStack` y no dos estados de la misma vista.
    private var pattern: some View {
        ZStack {
            // `TimelineView` redibuja al ritmo de la pantalla, pero **la
            // posición no la decide él**: cada fotograma vuelve a preguntar al
            // modelo, que la resuelve contra el origen que publicó el bucle del
            // scheduler. El movimiento deriva del reloj musical; lo que el
            // temporizador decide es cuándo repintar, no dónde está el tiempo.
            TimelineView(.animation(paused: !model.isPlaying)) { _ in
                RingView(ring: model.ring, playhead: model.playhead)
            }

            if let change = model.transientChange {
                transient(change)
            }
        }
        .frame(maxWidth: 420)
        .padding(24)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// El valor grande.
    ///
    /// Tipografía muy grande y jerarquía marcada porque el criterio es leerlo a
    /// Displays the description of a parameter change with its family-specific accent color.
    /// - Parameter change: The parameter change to display.
    /// - Returns: A view showing the change description.
    private func transient(_ change: ParameterChange) -> some View {
        Text(change.description)
            .font(.system(size: 64, weight: .bold, design: .default))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            // **El acento es el de la familia del parámetro que se movió**, no
            // uno fijo: `product-guidelines.md` pide que el color codifique qué
            // tipo de parámetro es. Girar Velocity y girar Steps tienen que
            // leerse distinto sin necesidad de leer la palabra.
            .foregroundStyle(Palette.accent(for: change.parameter.family))
            .padding(.horizontal, 24)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: change)
    }

    // MARK: - Transporte

    private var transport: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Torax H-0")
                .font(.largeTitle.weight(.semibold))

            HStack(spacing: 24) {
                Button(model.isPlaying ? "Stop" : "Play") {
                    model.isPlaying ? model.stop() : model.play()
                }
                .font(.title.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .disabled(!model.canPlay && !model.isPlaying)
                // Objetivo táctil holgado: se toca de pie, delante del sintetizador.
                .frame(minWidth: 160, minHeight: 60)

                destination
            }

            parameters
            input
        }
    }

    /// De dónde llegan los giros.
    ///
    /// Sin controlador conectado se dice el estado y **nada más**: la app es de
    /// solo lectura y transporte, que es lo que `product-guidelines.md`
    /// especifica. No se ofrece ninguna vía táctil para suplirlo.
    private var input: some View {
        HStack(spacing: 12) {
            Text(model.sourceStatus)
                .font(.body)
                .foregroundStyle(
                    model.isReadOnly ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white))

            if model.sourceSelection.available.count > 1 {
                Picker("Input", selection: sourceBinding) {
                    ForEach(model.sourceSelection.available, id: \.endpoint) { source in
                        Text(source.displayName).tag(source.endpoint)
                    }
                }
                .pickerStyle(.menu)
            }

            if model.isReadOnly {
                Text("read-only")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sourceBinding: Binding<MIDIEndpointRef> {
        Binding(
            get: { model.sourceSelection.selected?.endpoint ?? 0 },
            set: { endpoint in
                guard
                    let chosen = model.sourceSelection.available.first(where: {
                        $0.endpoint == endpoint
                    })
                else { return }
                model.selectSource(chosen)
            }
        )
    }

    /// Estado y elección del destino. Sin destino se informa, no se pide perdón.
    private var destination: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.outputUnavailable ?? model.destinationStatus)
                .font(.title2)
                .foregroundStyle(model.selection.hasEndpoint ? .white : .secondary)

            if model.selection.available.count > 1 {
                Picker("Destination", selection: destinationBinding) {
                    ForEach(model.selection.available, id: \.endpoint) { destination in
                        Text(destination.displayName).tag(destination.endpoint)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var destinationBinding: Binding<MIDIEndpointRef> {
        Binding(
            get: { model.selection.selected?.endpoint ?? 0 },
            set: { endpoint in
                guard
                    let chosen = model.selection.available.first(where: { $0.endpoint == endpoint })
                else { return }
                model.select(chosen)
            }
        )
    }

    /// Los valores de Shape y de Groove, en solo lectura.
    ///
    /// **Cada familia con su acento**, para que el estado en reposo se lea con
    /// el mismo código de color que el valor grande transitorio.
    ///
    /// No se muestra ninguna altura: el pool tiene su propia representación en
    /// `TonalView`, y enseñar una nota por paso contradiría el modelo de pool de
    /// la Pre Spec.
    private var parameters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.shapeSummary)
                .font(.title3.monospaced())
                .foregroundStyle(Palette.shape.opacity(0.85))
            Text(model.grooveSummary)
                .font(.title3.monospaced())
                .foregroundStyle(Palette.groove.opacity(0.85))
        }
    }

    // MARK: - Medición de jitter

    private var measurement: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jitter")
                .font(.title2.weight(.semibold))
            Text(jitter.statusMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            HStack(spacing: 20) {
                Button(jitter.isRunning ? "Detener" : "Medir") {
                    jitter.isRunning ? jitter.stop() : jitter.start()
                }
                .buttonStyle(.bordered)

                Picker("Eventos por tempo", selection: $jitter.sampleCount) {
                    ForEach(JitterMeasurementModel.sampleCountOptions, id: \.self) { count in
                        Text("\(count) eventos").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(jitter.isRunning)
                .frame(maxWidth: 320)
            }

            Text("Umbral: máx < 2 ms · σ < 0,5 ms")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let failure = jitter.failureMessage {
                Text(failure)
                    .font(.body.monospaced())
                    .foregroundStyle(.orange)
            }

            ForEach(jitter.measurements, id: \.beatsPerMinute) { measurement in
                row(for: measurement)
            }

            if let verdict = jitter.overallVerdict {
                Text(verdict ? "VEREDICTO: CUMPLE" : "VEREDICTO: NO CUMPLE")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(verdict ? .green : .red)
            }
        }
    }

    private func row(for measurement: JitterMeasurement) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("\(Int(measurement.beatsPerMinute)) BPM")
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(width: 90, alignment: .leading)

            Text(measurement.statistics.summary)
                .font(.callout.monospaced())
                .foregroundStyle(measurement.statistics.meetsTrackThreshold ? .green : .red)
        }
    }
}

#Preview {
    ContentView()
}
