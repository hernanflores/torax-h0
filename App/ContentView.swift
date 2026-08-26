import Engine
import MIDI
import SwiftUI

/// Placeholder del track `timing-spike_20260826`.
///
/// La UI real de este track (play/stop, tempo y resultados de jitter) llega en
/// la Fase 4. No lleva lenguaje visual de producto: es instrumentación.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Torax H-0")
                .font(.largeTitle.weight(.semibold))
            Text("Timing spike · schema v\(Engine.schemaVersion) · \(MIDIPackage.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
