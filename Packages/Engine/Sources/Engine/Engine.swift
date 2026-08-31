/// Engine — motor generativo de Torax H-0.
///
/// Vacío por diseño en el track `timing-spike_20260826`: el spike valida el
/// reloj MIDI, no la generatividad. El paquete se crea ya con su frontera de
/// dependencias impuesta para que el motor nazca puro y no haya que
/// desenredarlo después.
///
/// > **Renombrado el 2026-08-31, de `Engine` a `EngineSchema`.** Un `enum`
/// > llamado igual que su módulo hace imposible cualificar cualquier tipo del
/// > paquete: dentro de un fichero que importa `Engine`, el nombre resuelve al
/// > `enum` y `Engine.Pattern` deja de compilar. Y cualificar hace falta: los
/// > targets de test corren en macOS, donde XCTest arrastra `ApplicationServices`
/// > y con él un `Pattern` de Quickdraw que choca con el del dominio. El nombre
/// > del dominio es el de la Pre Spec y no se toca; el que sobra es este.
public enum EngineSchema {
    /// Versión del esquema del modelo persistido.
    ///
    /// Se declara desde el primer commit porque el modelo va a crecer al
    /// incorporar lo que v1 dejó fuera (Cycles, Random, LFO). Ver
    /// `conductor/tech-stack.md`.
    public static let schemaVersion = 1
}
