/// Qué altura tiene cada uno de los dieciséis pads del controlador.
///
/// **Un pad es un índice, no una altura.** El número de nota que envía el
/// controlador solo dice *qué pad se pulsó*; la altura la decide esta
/// superficie a partir del marco tonal y de la octava vigente. Son dos cosas
/// —la numeración del preset y el dominio musical— y hasta la rebanada 7 eran
/// una sola.
///
/// La disposición, en numeración de hardware:
///
/// | Pad | Contenido |
/// |---|---|
/// | 1–7 | Grados 1–7 de la escala, en la octava base |
/// | 9–15 | Los mismos grados, una octava por encima |
/// | 8 | Baja el registro una octava |
/// | 16 | Sube el registro una octava |
///
/// **El alineamiento por octava es la invariante que lo sostiene:** el pad 9 es
/// siempre el pad 1 más doce semitonos, sea cual sea la escala y el Root. Es lo
/// que permite llamar *octava* al desplazamiento sin mentir, y la razón de que
/// una escala de cinco grados deje cuatro pads apagados en vez de rellenarlos:
/// rellenar pondría el pad 9 a dos octavas y una tercera del pad 1, distinto
/// para cada escala, y la superficie dejaría de poder aprenderse.
public struct PadSurface: Equatable, Sendable {

    /// Los pads del controlador. Dieciséis, como los Value Buttons de la Pre
    /// Spec y como la fila del BeatStep Pro.
    public static let padCount = 16

    /// Cuántos pads lleva cada bloque antes del pad de octava.
    static let degreesPerBlock = 7

    /// La nota MIDI donde empieza la octava base: C2.
    ///
    /// **Es una octava, no una nota fija.** Con Root en Do el pad 1 es C2
    /// literalmente; con Root en Re es D2. El grado 1 es el Root por
    /// definición, y clavar el pad 1 en Do lo desalinearía de la escala.
    static let baseOctaveStart = 48

    public let frame: TonalFrame

    /// Octavas de desplazamiento sobre la base, con signo. Lo mueven los pads 8
    /// y 16.
    public let octaveShift: Int

    public init(frame: TonalFrame, octaveShift: Int = 0) {
        self.frame = frame
        self.octaveShift = octaveShift
    }

    /// La altura del pad, o `nil` si no tiene ninguna asignada.
    ///
    /// Devuelve `nil` para los pads de octava —el 8 y el 16, que desplazan en
    /// vez de sonar—, para los que sobran cuando la escala tiene menos de siete
    /// grados, y para cualquier índice fuera de la superficie. Los cuatro casos
    /// comparten criterio con un CC sin asignar: no es un error, no publica
    /// nada.
    public func pitch(at index: Int) -> Pitch? {
        guard (0..<Self.padCount).contains(index) else { return nil }

        let block = index / 8
        let offset = index % 8
        guard offset < Self.degreesPerBlock else { return nil }

        let degrees = frame.scale.degrees
        guard offset < degrees.count else { return nil }

        let octave = Self.baseOctaveStart + 12 * (block + octaveShift)
        return Pitch(octave + frame.root.pitchClass + degrees[offset])
    }
}
