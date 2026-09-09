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
    /// > **La regla valía solo para la entrada, y desde el 2026-09-09 vale para
    /// > los dos.** El `spec.md` de `midi-learn_20260908` decía que como salida
    /// > la sesión de red «no estorba a ningún estado especificado», y el iPad lo
    /// > desmintió: se autoseleccionaba como destino, así que **la app arrancaba
    /// > mandando las notas a la red en vez de a un sintetizador**. Sonar a
    /// > ninguna parte por defecto sí estorba.
    ///
    /// **Sigue siendo elegible a mano en los dos papeles**, y lo recordado sigue
    /// mandando: MIDI por red a otro equipo es una vía legítima de salida. Lo
    /// único que se le quita es elegirse sola.
    func isAutoSelectable(_ endpoint: MIDIEndpointInfo) -> Bool {
        isEligible(endpoint) && !endpoint.isNetworkSession
    }

    /// El endpoint que se puede elegir sin intervención.
    ///
    /// Un destino conserva la regla de «el primero»: con dos sintetizadores la
    /// app puede sonar y el usuario puede cambiarlo después. Dos fuentes, en
    /// cambio, pueden ser dos puertos del mismo controlador y CoreMIDI no da un
    /// discriminante estable para saber cuál lleva los controles. En ese caso
    /// no se adivina por el orden ni por el nombre: se deja la elección a la
    /// pantalla.
    func automaticEndpoint(in endpoints: [MIDIEndpointInfo]) -> MIDIEndpointInfo? {
        let candidates = endpoints.filter { isAutoSelectable($0) }
        switch self {
        case .destination:
            return candidates.first
        case .source:
            return candidates.count == 1 ? candidates[0] : nil
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

    private enum SelectionOrigin: Equatable, Sendable {
        case automatic
        case remembered
        case manual
    }

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

    /// Cómo se llegó a `selected`. Refrescar puede sustituir una caída
    /// automática por lo recordado, pero nunca una elección manual.
    private var selectionOrigin: SelectionOrigin?

    /// Lo que vino del disco sigue pendiente mientras el endpoint no exista.
    /// Se conserva también durante una caída automática, para recuperarlo si
    /// aparece en una notificación posterior.
    private var rememberedName: String?

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
        selectionOrigin = nil
        rememberedName = nil
    }

    /// A partir de la lista enumerada del sistema, recordando —si se sabe— cuál
    /// se eligió la última vez.
    ///
    /// **Lo recordado manda sobre la autoselección** (FR15 de
    /// `midi-learn_20260908`), **incluida la sesión de red**: haberla elegido a
    /// mano y guardado es una elección explícita, y la regla de no
    /// autoseleccionarla no la contradice. Si lo recordado todavía no está, se
    /// usa la caída automática normal sin olvidar la preferencia pendiente.
    ///
    /// Es lo que el plan de `network-session-source_20260828` dejó anotado:
    /// «cuando haya persistencia, recordar la última elección lo resuelve mejor
    /// que cualquier heurística».
    public init(
        _ role: MIDIEndpointRole,
        discovering systemEndpoints: [MIDIEndpointInfo],
        remembering name: String? = nil
    ) {
        var selection = MIDIEndpointSelection(role)
        selection.rememberedName = name
        self = selection.refreshed(with: systemEndpoints)
    }

    /// Vuelve a leer la lista del sistema conservando la elección del usuario.
    ///
    /// Si el endpoint elegido sigue presente se mantiene, aunque haya cambiado
    /// de posición: refrescar no puede mover la elección bajo los pies de quien
    /// la hizo. Si desapareció, se aplica otra vez la regla automática del
    /// papel, y se cae a `nil` cuando no hay una elección inequívoca.
    public func refreshed(with systemEndpoints: [MIDIEndpointInfo]) -> Self {
        var refreshed = self
        refreshed.available = systemEndpoints.filter(role.isEligible)

        // Una elección manual o recordada se conserva por identidad de endpoint,
        // aunque cambie el orden de la enumeración o haya nombres repetidos.
        if let selected, refreshed.available.contains(selected),
            selectionOrigin != .automatic
        {
            refreshed.selected = selected
            return refreshed
        }

        // Lo recordado puede llegar después del arranque. Solo sustituye una
        // caída automática (o el estado vacío); `selecting(_:)` borra lo
        // pendiente cuando el usuario elige otra cosa.
        if selectionOrigin != .manual, let rememberedName,
            let remembered = refreshed.available.first(where: {
                $0.displayName == rememberedName
            })
        {
            refreshed.selected = remembered
            refreshed.selectionOrigin = .remembered
            return refreshed
        }

        // Una fuente elegida automáticamente deja de ser inequívoca si aparece
        // una segunda. No se conserva solo porque llegara primero; un destino
        // automático sí puede seguir sonando mientras el usuario decide.
        if selectionOrigin == .automatic, role == .source {
            refreshed.selected = role.automaticEndpoint(in: refreshed.available)
            refreshed.selectionOrigin = refreshed.selected == nil ? nil : .automatic
            return refreshed
        }

        if let selected, refreshed.available.contains(selected) {
            refreshed.selected = selected
            return refreshed
        }

        refreshed.selected = role.automaticEndpoint(in: refreshed.available)
        refreshed.selectionOrigin = refreshed.selected == nil ? nil : .automatic
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
        updated.selectionOrigin = .manual
        updated.rememberedName = nil
        return updated
    }
}
