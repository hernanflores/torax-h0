/// Engine — motor generativo de Torax H-0.
///
/// Vacío por diseño en el track `timing-spike_20260826`: el spike valida el
/// reloj MIDI, no la generatividad. El paquete se crea ya con su frontera de
/// dependencias impuesta para que el motor nazca puro y no haya que
/// desenredarlo después.
public enum Engine {
    /// Versión del esquema del modelo persistido.
    ///
    /// Se declara desde el primer commit porque el modelo va a crecer al
    /// incorporar lo que v1 dejó fuera (Cycles, Random, LFO). Ver
    /// `conductor/tech-stack.md`.
    public static let schemaVersion = 1
}
