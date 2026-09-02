/// Los dieciséis anillos concéntricos, dispuestos.
///
/// **Es la pantalla 1 del handoff** (FR1): del exterior al interior, Track 1 al
/// 16, cada uno con su propio reparto. Lo que este tipo aporta sobre `Ring` es
/// *dónde* va cada anillo; el reparto de cada uno lo sigue haciendo `Ring`, que
/// ya documenta por qué no se recalcula en dos sitios.
///
/// **La geometría vive aquí y no en la vista**, por la razón de siempre
/// (`workflow.md`, NFR5): que dos anillos contiguos no se solapen es una
/// invariante, y una invariante que se rompe en silencio —dos anillos superpuestos
/// se siguen dibujando, solo que ilegibles— tiene que estar donde hay tests.
///
/// **Todo son fracciones del radio disponible**, en `(0, 1]`, igual que
/// `Ring.Position.turn` es fracción de vuelta. Quien dibuja conoce el tamaño de
/// la pantalla; este tipo no, y no debería: dibujar a cualquier tamaño es
/// multiplicar.
///
/// > **Las proporciones no son las del handoff, y no pueden serlo.** El
/// > click-through dibuja **cinco** anillos de 180 a 52px sobre un lienzo de
/// > 190px, es decir un paso de 16px de radio entre anillos. Dieciséis anillos
/// > con ese paso pedirían un lienzo tres veces mayor del que la pantalla
/// > reserva. Lo que se conserva es lo que el handoff decide de verdad —el orden
/// > exterior→interior, el paso constante y el hueco central— y lo que se
/// > recalcula es la escala, que es consecuencia de que sean dieciséis y no cinco.
///
/// No es código de tiempo real: construirlo asigna memoria. Se hace en el hilo
/// principal, para dibujar.
public struct RingStack: Equatable, Sendable {

    /// Un anillo y su sitio.
    public struct Band: Equatable, Sendable {

        /// Qué Track dibuja, de 0 a 15.
        public let track: Int

        /// Su reparto, ya resuelto.
        public let ring: Ring

        /// A qué distancia del centro, como fracción del radio disponible.
        public let radius: Double

        /// Si su Track tiene alturas que emitir.
        ///
        /// **Viaja en la banda para que la vista no tenga que volver al
        /// `Pattern`.** Decide *cómo* se dibuja —los que tienen material se
        /// distinguen de los vacíos sin leer texto— pero nunca *dónde*: el radio
        /// es el mismo con pool y sin él.
        public let hasMaterial: Bool
    }

    // MARK: - Las proporciones

    /// Dónde acaba el anillo más interior.
    ///
    /// Deja libre el centro, que es de donde nace la aguja del playhead. Sin
    /// hueco, la aguja saldría de debajo de una marca en vez de de un punto.
    public static let centreHole: Double = 0.28

    /// Dónde cae el anillo más exterior.
    ///
    /// No es 1: la marca se dibuja **centrada** sobre el anillo y sobresale
    /// medio diámetro hacia fuera, así que el anillo exterior tiene que dejarle
    /// ese margen o se recortaría contra el borde del lienzo.
    public static let outermost: Double = 0.97

    /// Radio de la marca de un Pulse.
    ///
    /// **El techo es medio paso**, o dos anillos contiguos se tocarían. Se queda
    /// por debajo con holgura: a un metro, dos marcas que casi se rozan se leen
    /// como una sola mancha aunque geométricamente no se solapen.
    public static let pulseMarkRadius: Double = 0.014

    /// Radio de la marca de un Step que no dispara.
    ///
    /// **Los huecos se ven, y eso es deliberado.** Es la misma decisión que
    /// `Palette.step` ya documenta para el anillo único: que el reparto
    /// euclidiano se lea exige ver también las posiciones que no disparan, o
    /// dieciséis posiciones de las que cinco disparan se leerían como cinco
    /// puntos sueltos.
    public static let stepMarkRadius: Double = 0.006

    /// Cuánto baja el radio de un anillo al siguiente.
    ///
    /// Constante a propósito: es lo que hace que dieciséis anillos se lean como
    /// una escala ordenada y no como un montón de círculos.
    public static var spacing: Double {
        (outermost - centreHole) / Double(Pattern.trackCount - 1)
    }

    // MARK: - Las bandas

    /// Los dieciséis, del exterior al interior.
    public let bands: [Band]

    /// Dispone los dieciséis Tracks del Pattern.
    ///
    /// **Los dieciséis siempre, tengan material o no** (FR1). Un anillo que
    /// apareciera y desapareciera con el material movería a los demás de sitio,
    /// y eso es movimiento no derivado del reloj musical, que
    /// `product-guidelines.md` prohíbe.
    public init(pattern: Pattern) {
        bands = (0..<Pattern.trackCount).map { index in
            let track = pattern.track(at: index) ?? Pattern.emptyTrack
            return Band(
                track: index,
                ring: Ring(shape: track.shape),
                radius: Self.outermost - Self.spacing * Double(index),
                hasMaterial: !track.pool.isEmpty
            )
        }
    }
}

extension RingStack {

    /// El grosor del arco de un anillo, como fracción del radio disponible.
    ///
    /// **Es una fracción del paso**, no un valor suelto: si fuera absoluto,
    /// cambiar el número de anillos lo dejaría o solapado o flotando. Se queda
    /// por debajo del paso para que quede una separación oscura entre bandas,
    /// que es lo que las hace contables.
    public static var bandWidth: Double { spacing * 0.62 }
}
