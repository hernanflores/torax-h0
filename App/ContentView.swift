import CoreMIDI
import MIDI
import SwiftUI

/// Pantalla mínima de estado.
///
/// **Sin el lenguaje visual del producto.** Ni anillo circular, ni overlay de
/// valor grande, ni acentos por familia: eso llega en el track de UI. Aquí solo
/// se ve el transporte, el destino y los valores de Shape, y **nada de eso es
/// editable**.
///
/// Que no lo sea no es un recorte: es el estado «sin controlador conectado» que
/// `product-guidelines.md` especifica —solo lectura y transporte—. Un slider
/// provisional para Steps o Pulses sería el antipatrón que ese documento nombra
/// y habría que desmontarlo después.
///
/// El panel de medición de jitter sigue debajo porque la Fase 4 del track exige
/// medir «con el motor y la interfaz corriendo»: tienen que convivir en la misma
/// pantalla, no en pestañas que se excluyan.
struct ContentView: View {

    @State private var model = TransportModel()
    @State private var jitter = JitterMeasurementModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                transport
                Divider().overlay(.white.opacity(0.2))
                measurement
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .onAppear { jitter.startIfRequestedByLaunchArguments() }
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

            shape
        }
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
                guard let chosen = model.selection.available.first(where: { $0.endpoint == endpoint })
                else { return }
                model.select(chosen)
            }
        )
    }

    /// Los valores de Shape, en solo lectura.
    ///
    /// No se muestra ninguna altura: la nota de esta rebanada es una constante
    /// provisional del camino MIDI, y enseñarla sugeriría una nota fija por
    /// paso, que contradice el modelo de pool de la Pre Spec.
    private var shape: some View {
        Text(model.shapeSummary)
            .font(.title3.monospaced())
            .foregroundStyle(.secondary)
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
