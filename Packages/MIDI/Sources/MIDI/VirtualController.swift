import Engine

#if DEBUG

    /// Controlador de desarrollo que inyecta giros sin hardware.
    ///
    /// **Existe porque la frontera táctil/knob lo obliga.** `product-guidelines.md`
    /// reserva los parámetros generativos a los knobs y deja la pantalla para
    /// configuración y transporte; sin controlador conectado la app es de solo
    /// lectura. Probar el motor sin hardware no puede hacerse abriendo una puerta de
    /// edición táctil, así que se hace con esto — y el propio documento lo nombra:
    /// «es una herramienta de test, excluida del build de producción; **no es un
    /// modo de edición táctil por la puerta de atrás**».
    ///
    /// **Produce mensajes MIDI de verdad, no atajos.** Codifica el giro con la misma
    /// convención que usaría el hardware y lo entrega por el mismo camino, así que
    /// lo que se prueba con él es el camino que corre en producción. Un inyector que
    /// llamara directamente a `Shape.applying` no probaría ni la decodificación ni
    /// el mapeo.
    ///
    /// **Compilado solo en Debug.** El `#if DEBUG` es lo que garantiza que no viaja
    /// en el binario de producción; es la misma clase de problema que
    /// `UIBackgroundModes`, que compila igual y solo se nota en el producto final,
    /// así que se verifica sobre el binario y no por inspección.
    public struct VirtualController: Sendable {

        public let channel: MIDIChannel
        public let mapping: ControlMapping
        public let encoding: RelativeEncoding

        /// Canal 1 es un literal dentro de rango, así que el desempaquetado no
        /// puede fallar. Es la justificación que `swift.md` exige para un `!`.
        public init(
            channel: MIDIChannel = MIDIChannel(1)!,
            mapping: ControlMapping = .beatStepPro,
            encoding: RelativeEncoding = .twosComplement
        ) {
            self.channel = channel
            self.mapping = mapping
            self.encoding = encoding
        }

        /// El mensaje que mandaría un knob al girar `steps` posiciones.
        ///
        /// Devuelve `nil` si el parámetro no está mapeado o si el giro no se puede
        /// Creates a MIDI control-change message for turning a track parameter.
        /// - Parameters:
        ///   - parameter: The track parameter to control.
        ///   - steps: The number of relative steps to turn.
        /// - Returns: A MIDI control-change message, or `nil` when the parameter has no mapped controller or the steps cannot be encoded.
        public func turn(_ parameter: TrackParameter, by steps: Int) -> MIDIMessage? {
            guard let controller = mapping.controller(for: parameter),
                let value = encoding.value(for: steps)
            else { return nil }

            return .controlChange(channel: channel, controller: controller, value: value)
        }
    }

#endif
