/// MIDI — reloj, scheduling y salida CoreMIDI de Torax H-0.
///
/// El contenido real llega en la Fase 2 del track `timing-spike_20260826`:
/// modelo de tiempo musical, scheduler look-ahead y cliente CoreMIDI.
public enum MIDIPackage {
    /// Marcador de existencia del paquete hasta que llegue la Fase 2.
    public static let name = "MIDI"
}
