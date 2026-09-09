import CoreMIDI

/// Lo que CoreMIDI dice de un endpoint, ya leído y sin CoreMIDI dentro.
///
/// **Existe para poder decidir qué distingue a la sesión MIDI de red.** iPadOS
/// publica siempre `Red Session 1` como fuente, la app la autoselecciona y el
/// controlador real no se elige solo al conectarlo. Identificarla por el nombre
/// visible está descartado —depende del idioma del sistema y de lo que el
/// usuario le haya puesto—, así que hace falta una propiedad. Cuál, se decide
/// mirando lo que el dispositivo devuelve de verdad, no adivinando.
///
/// **Es un valor, y por eso se puede testear sin hardware.** La lectura de
/// CoreMIDI vive en su costura y no se testea, como el resto de las costuras de
/// este paquete; lo que sí se cubre es que el informe no esconda nada.
public struct EndpointProperties: Equatable, Sendable {

    /// El nombre que se enseña en el selector. **No sirve para identificar**
    /// (NFR4 del track), y está aquí solo para saber de qué endpoint habla cada
    /// bloque del informe.
    public let displayName: String

    public let name: String?
    public let model: String?
    public let manufacturer: String?

    /// Quién publica el endpoint. Es la candidata con mejor pinta: la sesión de
    /// red la publica el driver RTP de Apple, y un controlador por USB no.
    public let driverOwner: String?

    public let uniqueID: Int32?
    public let isOffline: Bool?

    /// Si el endpoint cuelga de una entidad.
    ///
    /// **Un endpoint virtual no tiene**, y eso por sí solo ya podría separar las
    /// dos familias. Se lee aparte de los nombres porque es una pregunta de
    /// estructura y no una cadena.
    public let hasEntity: Bool

    /// Nombre y driver del dispositivo padre, cuando lo hay.
    public let deviceName: String?
    public let deviceDriverOwner: String?

    /// El volcado entero de propiedades, tal cual lo da CoreMIDI.
    ///
    /// **Es la red bajo el trapecio.** Las candidatas de arriba son una apuesta;
    /// si ninguna distingue, la respuesta está en alguna propiedad que nadie
    /// pensó en pedir, y sin volcado habría que volver al iPad a por ella.
    public let allProperties: String?

    public init(
        displayName: String,
        name: String?,
        model: String?,
        manufacturer: String?,
        driverOwner: String?,
        uniqueID: Int32?,
        isOffline: Bool?,
        hasEntity: Bool,
        deviceName: String?,
        deviceDriverOwner: String?,
        allProperties: String?
    ) {
        self.displayName = displayName
        self.name = name
        self.model = model
        self.manufacturer = manufacturer
        self.driverOwner = driverOwner
        self.uniqueID = uniqueID
        self.isOffline = isOffline
        self.hasEntity = hasEntity
        self.deviceName = deviceName
        self.deviceDriverOwner = deviceDriverOwner
        self.allProperties = allProperties
    }
}

/// El informe de diagnóstico de fuentes MIDI, para leerlo en un iPad.
///
/// **El destino de este texto es una git note.** La Fase 2 del track
/// `midi-learn_20260908` pide registrar «lo que devuelve cada candidata, con el
/// valor observado», y de ahí sale la decisión de qué propiedad identifica a la
/// sesión de red. Así que el formato es el de algo que se pega en un fichero y
/// se lee dentro de un año: una etiqueta por línea y nada de tablas anchas.
///
/// No es código de tiempo real: se llama al arrancar, y leer nombres asigna.
public enum EndpointDiagnostics {

    /// Cómo se escribe una propiedad que no está.
    ///
    /// **Ausente y no leída tienen que ser distinguibles.** Si el informe se
    /// saltara las propiedades que no están, «esta fuente no declara
    /// `driverOwner`» —que es un dato, y puede ser *el* dato— parecería que a
    /// alguien se le olvidó leerlo.
    public static let absent = "(ausente)"

    /// El informe de todas las fuentes.
    public static func report(for sources: [EndpointProperties]) -> String {
        guard !sources.isEmpty else {
            return """
                MIDI sources: 0 — no sources.
                En un iPad esto no debería pasar: iPadOS publica siempre la sesión \
                de red. Si sale aquí, es que se está mirando en otro sitio.
                """
        }

        let blocks = sources.enumerated().map { index, source in
            block(for: source, number: index + 1)
        }

        return (["MIDI sources: \(sources.count)"] + blocks).joined(separator: "\n\n")
    }

    private static func block(for source: EndpointProperties, number: Int) -> String {
        var lines = [
            "[\(number)] \(source.displayName)",
            "  name:              \(written(source.name))",
            "  model:             \(written(source.model))",
            "  manufacturer:      \(written(source.manufacturer))",
            "  driverOwner:       \(written(source.driverOwner))",
            "  uniqueID:          \(written(source.uniqueID.map(String.init)))",
            "  offline:           \(written(source.isOffline.map(String.init)))",
            "  entity:            \(source.hasEntity ? "sí" : "no")",
            "  device:            \(written(source.deviceName))",
            "  deviceDriver:      \(written(source.deviceDriverOwner))",
        ]

        if let dump = source.allProperties {
            lines.append("  --- volcado entero ---")
            lines.append(dump)
        }

        return lines.joined(separator: "\n")
    }

    private static func written(_ value: String?) -> String { value ?? absent }
}

extension EndpointDiagnostics {

    /// Lee las propiedades de un endpoint de CoreMIDI.
    ///
    /// **Es la costura, y no lleva tests**: hace falta un endpoint para
    /// ejercitarla, y el que importa solo existe en un iPad. Lo que se prueba es
    /// el informe que sale de aquí.
    ///
    /// No es código de tiempo real.
    public static func properties(of endpoint: MIDIEndpointRef) -> EndpointProperties {
        var entity = MIDIEntityRef()
        let hasEntity = MIDIEndpointGetEntity(endpoint, &entity) == noErr && entity != 0

        var device = MIDIDeviceRef()
        let hasDevice = hasEntity && MIDIEntityGetDevice(entity, &device) == noErr && device != 0

        return EndpointProperties(
            displayName: CoreMIDIOutput.displayName(of: endpoint),
            name: string(kMIDIPropertyName, of: endpoint),
            model: string(kMIDIPropertyModel, of: endpoint),
            manufacturer: string(kMIDIPropertyManufacturer, of: endpoint),
            driverOwner: string(kMIDIPropertyDriverOwner, of: endpoint),
            uniqueID: integer(kMIDIPropertyUniqueID, of: endpoint),
            isOffline: integer(kMIDIPropertyOffline, of: endpoint).map { $0 != 0 },
            hasEntity: hasEntity,
            deviceName: hasDevice ? string(kMIDIPropertyName, of: device) : nil,
            deviceDriverOwner: hasDevice ? string(kMIDIPropertyDriverOwner, of: device) : nil,
            allProperties: dump(of: endpoint)
        )
    }

    /// El informe de las fuentes presentes en el sistema.
    ///
    /// No es código de tiempo real.
    public static func reportForSystemSources() -> String {
        report(
            for: (0..<MIDIGetNumberOfSources()).map { properties(of: MIDIGetSource($0)) }
        )
    }

    /// El driver que publica la sesión MIDI de red de iPadOS.
    ///
    /// **Observado en dispositivo el 2026-09-09**, con cuatro fuentes delante:
    /// `Red Session 1` declara esto, y el BeatStep Pro —sus dos puertos— y el
    /// OP-Z declaran `com.apple.AppleMIDIUSBDriver`. La comparación es por
    /// driver y no por nombre visible, que depende del idioma del sistema y de
    /// lo que el usuario le haya puesto (NFR4).
    ///
    /// **Si iPadOS lo cambia, esto deja de distinguir y todo vuelve a
    /// autoseleccionar la red.** El diagnóstico que encontró el valor sigue en
    /// este fichero para poder mirarlo otra vez, y los valores observados están
    /// en la git note de la Fase 2 del track.
    static let networkDriverOwner = "com.apple.AppleMIDINetworkDriver"

    /// Si ese endpoint lo publica la sesión de red.
    ///
    /// No es código de tiempo real: se consulta al enumerar.
    public static func isNetworkSession(_ endpoint: MIDIEndpointRef) -> Bool {
        string(kMIDIPropertyDriverOwner, of: endpoint) == networkDriverOwner
    }

    private static func string(_ property: CFString, of object: MIDIObjectRef) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    private static func integer(_ property: CFString, of object: MIDIObjectRef) -> Int32? {
        var value: Int32 = 0
        guard MIDIObjectGetIntegerProperty(object, property, &value) == noErr else { return nil }
        return value
    }

    private static func dump(of object: MIDIObjectRef) -> String? {
        var properties: Unmanaged<CFPropertyList>?
        guard MIDIObjectGetProperties(object, &properties, true) == noErr, let properties else {
            return nil
        }
        return String(describing: properties.takeRetainedValue())
    }
}
