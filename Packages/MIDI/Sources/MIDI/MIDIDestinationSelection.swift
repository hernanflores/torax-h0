/// Los destinos MIDI elegibles del sistema y cuál está elegido.
///
/// **Es un valor, no un objeto que consulte al sistema.** Recibe la lista ya
/// enumerada y decide qué hacer con ella. Así la lógica —qué es elegible, qué
/// pasa al refrescar, qué significa no tener nada— se testea sin sintetizadores
/// conectados, que es lo único que hay en la máquina de CI.
///
/// La enumeración real vive en `CoreMIDIOutput.availableDestinations()`.
public struct MIDIDestinationSelection: Equatable, Sendable {

    /// Destinos que el usuario puede elegir.
    public private(set) var available: [MIDIDestination]

    /// Destino elegido, o `nil` si no hay ninguno.
    ///
    /// `nil` es el estado **No MIDI device**: no es un error ni un fallo de
    /// arranque, es lo que se ve cuando no hay nada enchufado. En un
    /// secuenciador desenchufar el cable a media sesión es algo que pasa
    /// (`conductor/code_styleguides/swift.md`).
    public private(set) var selected: MIDIDestination?

    public var hasDestination: Bool { selected != nil }

    /// Sin nada conectado.
    public init() {
        available = []
        selected = nil
    }

    /// A partir de la lista enumerada del sistema.
    public init(discovering systemDestinations: [MIDIDestination]) {
        self = MIDIDestinationSelection().refreshed(with: systemDestinations)
    }

    /// Vuelve a leer la lista del sistema conservando la elección del usuario.
    ///
    /// Si el destino elegido sigue presente se mantiene, aunque haya cambiado de
    /// posición: refrescar no puede mover la elección bajo los pies de quien la
    /// hizo. Si desapareció, se cae al primero disponible, y a `nil` si no queda
    /// ninguno.
    public func refreshed(with systemDestinations: [MIDIDestination]) -> Self {
        var refreshed = self
        refreshed.available = systemDestinations.filter(Self.isEligible)

        if let selected, refreshed.available.contains(selected) {
            refreshed.selected = selected
        } else {
            // Elegir solo el primero es deliberado: con un sintetizador
            // conectado, pulsar Play tiene que sonar sin pasar antes por un
            // selector.
            refreshed.selected = refreshed.available.first
        }
        return refreshed
    }

    /// Elige un destino de la lista.
    ///
    /// Elegir algo que no está en la lista se ignora en lugar de fallar: la
    /// lista pudo cambiar entre que se dibujó la pantalla y que se tocó.
    public func selecting(_ destination: MIDIDestination) -> Self {
        guard available.contains(destination) else { return self }
        var updated = self
        updated.selected = destination
        return updated
    }

    /// El endpoint del arnés de medición no es un destino elegible.
    ///
    /// Durante la medición de jitter el arnés y la app corren a la vez, así que
    /// su endpoint virtual aparece en la lista del sistema junto a los
    /// sintetizadores reales. Elegirlo mandaría las notas al medidor.
    ///
    /// Se filtra por nombre y no por referencia de endpoint porque quien
    /// construye esta lista no conoce al arnés: cuando la app corre sola, el
    /// endpoint ni siquiera existe.
    private static func isEligible(_ destination: MIDIDestination) -> Bool {
        destination.displayName != VirtualLoopback.defaultName
    }
}

extension MIDIDestinationSelection {

    /// Cómo se comunica el estado de la salida.
    ///
    /// `product-guidelines.md`: «Sin mensajes de error emotivos. Un dispositivo
    /// MIDI desconectado se comunica con un estado (`No MIDI device`), no con
    /// una disculpa.» Sin destino se dice qué hay, no qué ha fallado; con
    /// destino se dice su nombre y nada más.
    ///
    /// En inglés y sin traducir, como el resto del vocabulario de la interfaz.
    public var statusDescription: String {
        selected?.displayName ?? "No MIDI device"
    }
}
