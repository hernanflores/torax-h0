import CoreMIDI
/// Un endpoint MIDI del sistema: de dónde llega o a dónde va el material.
public struct MIDIEndpointInfo: Hashable, Sendable {
    public let endpoint: MIDIEndpointRef
    public let displayName: String

    /// Si lo publica la sesión MIDI de red del sistema.
    ///
    /// **No se deduce del nombre visible** (NFR4 de
    /// `network-session-source_20260828`): el nombre depende del idioma del
    /// sistema y de lo que el usuario le haya puesto. Sale de
    /// `kMIDIPropertyDriverOwner`, que el diagnóstico del 2026-09-09 en iPad
    /// confirmó como el discriminante — la sesión de red declara
    /// `com.apple.AppleMIDINetworkDriver` y los controladores por USB
    /// `com.apple.AppleMIDIUSBDriver`.
    ///
    /// **Por defecto, `false`.** Un endpoint construido a mano —en un test, o
    /// por quien no tenga CoreMIDI delante— no es la sesión de red, y esa es la
    /// respuesta segura: como mucho hace que algo se autoseleccione, nunca que
    /// deje de poder elegirse.
    public let isNetworkSession: Bool

    public init(
        endpoint: MIDIEndpointRef, displayName: String, isNetworkSession: Bool = false
    ) {
        self.endpoint = endpoint
        self.displayName = displayName
        self.isNetworkSession = isNetworkSession
    }
}

/// Para qué se usa un endpoint.
///
/// **Existe para que la lógica de selección se escriba una vez.** Enumerar,
/// elegir, conservar la elección al refrescar y caer a «no hay ninguno» es
/// idéntico para la entrada y la salida; lo único que cambia es qué endpoints
/// son elegibles y cómo se dice que no hay ninguno. Eso es lo que lleva este
/// tipo, en vez de duplicar el resto.
public enum MIDIEndpointRole: Equatable, Sendable {

    /// A dónde se envían las notas.
    case destination

    /// De dónde llegan los mensajes del controlador.
    case source

    /// Cómo se comunica que no hay ninguno.
    ///
    /// `product-guidelines.md`: «un dispositivo MIDI desconectado se comunica
    /// con un estado, no con una disculpa». En inglés y sin traducir, como el
    /// resto del vocabulario de interfaz.
    var emptyStateDescription: String {
        switch self {
        case .destination: "No MIDI device"
        case .source: "No MIDI input"
        }
    }

    /// Si un endpoint puede elegirse para este papel.
    ///
    /// Los endpoints que crea la propia app se excluyen **solo como destino**:
    /// durante la medición de jitter el arnés y la app corren a la vez y
    /// aparecería entre los sintetizadores. Como fuente no hace falta filtrarlo,
    /// porque son destinos virtuales y nunca aparecen en la lista de entradas.
    ///
    /// **Se pregunta por los dos nombres, no por uno.** El arnés crea el suyo
    /// con un nombre distinto del de `VirtualLoopback.defaultName`, así que
    /// comparar con ese solo dejaba pasar justo el que importa: elegirlo como
    /// destino manda las notas de la app al arnés y ensucia la medición.
    func isEligible(_ endpoint: MIDIEndpointInfo) -> Bool {
        switch self {
        case .destination: !VirtualLoopback.isOwn(endpoint.displayName)
        case .source: true
        }
    }

    /// Si un endpoint puede elegirse **solo**, sin que nadie lo pida.
    ///
    /// **Elegible y autoseleccionable no son lo mismo, y esa distinción es todo
    /// el arreglo** (`network-session-source_20260828`). iPadOS publica siempre
    /// la sesión de red como fuente, así que la lista nunca está vacía: la app
    /// la elegía sola, el estado `No MIDI input` era inalcanzable en el
    /// dispositivo de destino, y el controlador real no se elegía al conectarlo.
    ///
    /// **La regla es de la entrada.** Como salida, la sesión de red es una vía
    /// legítima y no estorba a ningún estado especificado.
    func isAutoSelectable(_ endpoint: MIDIEndpointInfo) -> Bool {
        switch self {
        case .destination: isEligible(endpoint)
        case .source: isEligible(endpoint) && !endpoint.isNetworkSession
        }
    }
}

/// Los endpoints elegibles del sistema para un papel, y cuál está elegido.
///
/// **Es un valor, no un objeto que consulte al sistema.** Recibe la lista ya
/// enumerada y decide qué hacer con ella, así que la lógica se testea sin
/// hardware conectado — que es lo único que hay en la máquina de CI. La
/// enumeración real vive en `CoreMIDIOutput` y `CoreMIDIInput`.
public struct MIDIEndpointSelection: Equatable, Sendable {

    /// Para qué sirven los endpoints de esta selección.
    public let role: MIDIEndpointRole

    /// Endpoints que el usuario puede elegir.
    public private(set) var available: [MIDIEndpointInfo]

    /// Endpoint elegido, o `nil` si no hay ninguno.
    ///
    /// `nil` no es un error ni un fallo de arranque: es lo que se ve cuando no
    /// hay nada enchufado. En un secuenciador, desenchufar el cable a media
    /// sesión es algo que pasa.
    public private(set) var selected: MIDIEndpointInfo?

    public var hasEndpoint: Bool { selected != nil }

    /// Nombre del endpoint elegido, o el estado vacío del papel.
    public var statusDescription: String {
        selected?.displayName ?? role.emptyStateDescription
    }

    /// Sin nada conectado.
    public init(_ role: MIDIEndpointRole) {
        self.role = role
        available = []
        selected = nil
    }

    /// A partir de la lista enumerada del sistema, recordando —si se sabe— cuál
    /// se eligió la última vez.
    ///
    /// **Lo recordado manda sobre la autoselección** (FR15 de
    /// `midi-learn_20260908`), **incluida la sesión de red**: haberla elegido a
    /// mano y guardado es una elección explícita, y la regla de no
    /// autoseleccionarla no la contradice. Si lo recordado ya no está, se cae a
    /// la autoselección normal.
    ///
    /// Es lo que el plan de `network-session-source_20260828` dejó anotado:
    /// «cuando haya persistencia, recordar la última elección lo resuelve mejor
    /// que cualquier heurística».
    public init(
        _ role: MIDIEndpointRole,
        discovering systemEndpoints: [MIDIEndpointInfo],
        remembering name: String? = nil
    ) {
        var selection = MIDIEndpointSelection(role).refreshed(with: systemEndpoints)

        if let name,
            let remembered = selection.available.first(where: { $0.displayName == name })
        {
            selection = selection.selecting(remembered)
        }

        self = selection
    }

    /// Vuelve a leer la lista del sistema conservando la elección del usuario.
    ///
    /// Si el endpoint elegido sigue presente se mantiene, aunque haya cambiado
    /// de posición: refrescar no puede mover la elección bajo los pies de quien
    /// la hizo. Si desapareció, se cae al primero disponible, y a `nil` si no
    /// queda ninguno.
    public func refreshed(with systemEndpoints: [MIDIEndpointInfo]) -> Self {
        var refreshed = self
        refreshed.available = systemEndpoints.filter(role.isEligible)

        if let selected, refreshed.available.contains(selected) {
            refreshed.selected = selected
        } else {
            // Elegir solo el primero es deliberado: con algo conectado, la app
            // tiene que funcionar sin pasar antes por un selector. **El primero
            // que se pueda elegir solo**, que no es lo mismo que el primero de
            // la lista: la sesión de red va siempre delante y nunca se elige
            // sola.
            refreshed.selected = refreshed.available.first(where: role.isAutoSelectable)
        }
        return refreshed
    }

    /// Elige un endpoint de la lista.
    ///
    /// Elegir algo que no está en la lista se ignora en lugar de fallar: la
    /// lista pudo cambiar entre que se dibujó la pantalla y que se tocó.
    public func selecting(_ endpoint: MIDIEndpointInfo) -> Self {
        guard available.contains(endpoint) else { return self }
        var updated = self
        updated.selected = endpoint
        return updated
    }
}
