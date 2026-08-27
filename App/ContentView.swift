import MIDI
import SwiftUI

/// Pantalla de medición de jitter.
///
/// **Es instrumentación, no producto.** No lleva el lenguaje visual de
/// `product-guidelines.md` —ni anillo, ni pool tonal, ni acentos por familia—
/// porque no representa material musical: representa un experimento. La interfaz
/// del producto llega en tracks posteriores.
struct ContentView: View {

    @State private var model = JitterMeasurementModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            controls
            results
            Spacer()
            footnote
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
        .foregroundStyle(.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Torax H-0 · Timing Spike")
                .font(.largeTitle.weight(.semibold))
            Text(model.statusMessage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button(model.isRunning ? "Detener" : "Medir") {
                model.isRunning ? model.stop() : model.start()
            }
            .font(.title2.weight(.semibold))
            .buttonStyle(.borderedProminent)

            Picker("Eventos por tempo", selection: $model.sampleCount) {
                ForEach(JitterMeasurementModel.sampleCountOptions, id: \.self) { count in
                    Text("\(count) eventos").tag(count)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRunning)
            .frame(maxWidth: 340)
        }
    }

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Umbral: máx < 2 ms · σ < 0,5 ms")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let failure = model.failureMessage {
                Text(failure)
                    .font(.body.monospaced())
                    .foregroundStyle(.orange)
            }

            ForEach(model.measurements, id: \.beatsPerMinute) { measurement in
                row(for: measurement)
            }

            if let verdict = model.overallVerdict {
                Text(verdict ? "VEREDICTO: CUMPLE" : "VEREDICTO: NO CUMPLE")
                    .font(.title.weight(.bold))
                    .foregroundStyle(verdict ? .green : .red)
                    .padding(.top, 8)
            }
        }
    }

    private func row(for measurement: JitterMeasurement) -> some View {
        let statistics = measurement.statistics
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("\(Int(measurement.beatsPerMinute)) BPM")
                .font(.title2.weight(.semibold).monospacedDigit())
                .frame(width: 120, alignment: .leading)

            Text(statistics.summary)
                .font(.body.monospaced())
                .foregroundStyle(statistics.meetsTrackThreshold ? .green : .red)
        }
    }

    private var footnote: some View {
        Text("""
             La media con signo es el sesgo constante del camino de medición, no jitter. \
             La σ es lo que decide la estabilidad musical. El loopback es virtual: \
             no cruza el cable USB.
             """)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    ContentView()
}
