/// Mira si el transporte cambió de estado desde el último cuadro (FR6, FR7).
///
/// **Es la vía de vuelta del transporte, y por eso es un poll y no un callback.**
/// El hilo de recepción de CoreMIDI publica una palabra atómica al arrancar y al
/// parar —`Transport.transportGeneration` y `Transport.isSounding`—, y llamar
/// hacia el modelo desde ahí sería trabajo en el camino de tiempo real. La app
/// pregunta desde el `.task` de 16 ms que ya existe, el mismo de
/// `applyPendingAdoption()`.
///
/// **Hermana de `PendingAdoption`**, y por la misma razón: la decisión de si hay
/// algo que aplicar vive en `MIDI`, donde hay tests, porque `App` no se mide
/// (`workflow.md`). Lo que queda arriba es una llamada y una asignación.
///
/// **Sigue el contador y no el flag**, que es la razón de que FR1 pida un
/// contador. Un Start del maestro sobre un transporte que ya suena lo reinicia:
/// el flag acaba donde estaba y la rejilla es otra, así que mirar solo el flag
/// se perdería el cambio.
///
/// **No es `Sendable` a propósito.** Vive en el modelo, que está aislado al hilo
/// principal; lo que cruza hilos son los atómicos del transporte, no esto.
public final class TransportWatch {

    /// El contador que se vio la última vez que se reportó algo.
    ///
    /// Arranca en cero, que es el valor con el que nace un transporte recién
    /// construido: así un transporte parado y quieto no reporta nada en el
    /// primer cuadro, y uno que ya sonaba sí.
    private var lastSeenGeneration: UInt64 = 0

    public init() {}

    /// Si el transporte cambió, el estado en el que quedó. Si no, `nil`.
    ///
    /// **Devuelve el estado y no el contador** porque quien lo llama quiere
    /// saber si suena; el contador solo sirve para saber que hay algo nuevo que
    /// mirar.
    ///
    /// **Manda el estado final, no el recorrido.** Arrancar y parar dentro del
    /// mismo cuadro deja el contador en dos y el flag abajo: lo que se reporta es
    /// que no suena. El estado intermedio nunca fue visible, y FR11 ya declara
    /// que la pantalla puede ir un cuadro por detrás de lo que se oye.
    ///
    /// **Reportar consume el cambio**: el cuadro siguiente sin nada nuevo
    /// devuelve `nil`, o el modelo invalidaría la pantalla en cada cuadro
    /// después de cada transición.
    ///
    /// - Parameters:
    ///   - generation: `Transport.transportGeneration` ahora mismo.
    ///   - isSounding: `Transport.isSounding` ahora mismo.
    public func changed(generation: UInt64, isSounding: Bool) -> Bool? {
        guard generation != lastSeenGeneration else { return nil }

        lastSeenGeneration = generation
        return isSounding
    }
}
