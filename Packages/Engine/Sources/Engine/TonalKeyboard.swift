/// Las doce teclas de la pantalla de Scale & Root.
///
/// **Qué notas están en la escala y cuál es la raíz salen del marco tonal, no de
/// la vista.** Es la regla de siempre (`workflow.md`): una tecla mal clasificada
/// se dibuja igual de bien que una bien clasificada, así que la clasificación
/// vive donde hay tests y la vista solo pinta alturas de barra.
///
/// **Las doce existen siempre.** Las que no están en la escala se dibujan cortas
/// y oscuras, pero se dibujan: si aparecieran y desaparecieran al cambiar de
/// escala, las demás se moverían de sitio. Es el mismo criterio que mantiene los
/// dieciséis anillos en pantalla tengan material o no.
public struct TonalKeyboard: Equatable, Sendable {

    /// Una clase de altura, y qué papel juega en el marco vigente.
    public struct Key: Equatable, Sendable {

        /// Dónde cae en la octava, de 0 a 11.
        public let pitchClass: Int

        /// Su nombre, en la convención de `Root`: sostenidos y no bemoles.
        public let name: String

        /// Si pertenece a la escala vigente.
        ///
        /// Decide **cómo se dibuja** —alta o corta y oscura— y nada más.
        public let isInScale: Bool

        /// Si es la fundamental.
        ///
        /// **No es lo mismo que `isInScale`**, y por eso es una propiedad propia
        /// y no «la primera que esté dentro». El handoff se molesta en señalar
        /// esa confusión —la raíz lleva un tratamiento distinto del de «está en
        /// la escala»— porque en el gráfico las dos cosas se parecen.
        public let isRoot: Bool

        /// Si tocarla puede convertirla en la fundamental. **Siempre.**
        ///
        /// > **Aquí no se sigue al handoff, y conviene saber por qué.** Su mock
        /// > dibuja las notas de fuera de la escala como no interactivas, y
        /// > aplicarlo sería una confusión de categorías. «¿Está C# en Do
        /// > menor?» es una pregunta sobre el marco *actual*; elegir C# como
        /// > raíz construye un marco *nuevo* en el que C# es la fundamental y
        /// > está dentro por definición —el grado 1 es siempre el 0—.
        /// >
        /// > Con la regla del mock, qué tonalidades son alcanzables dependería de
        /// > la que esté puesta: desde Do menor no se podría ir a Do sostenido
        /// > menor sin pasar por otra, y el rodeo sería distinto según dónde se
        /// > esté. Es exactamente «de una manera que no se puede aprender», que
        /// > es el reproche que la Pre Spec le hace al mecanismo de pads que
        /// > descartó.
        ///
        /// Existe como propiedad, y no como una constante suelta en la vista,
        /// para que la decisión esté escrita donde se puede leer y probar.
        public var canBecomeRoot: Bool { true }
    }

    public let frame: TonalFrame

    /// Las doce, en orden de clase de altura.
    public let keys: [Key]

    public init(frame: TonalFrame) {
        self.frame = frame
        keys = (0..<12).map { pitchClass in
            let root = Root(pitchClass)!
            return Key(
                pitchClass: pitchClass,
                name: root.description,
                // Se pregunta al marco en vez de recorrer los grados: `allows`
                // ya sabe de la máscara transpuesta, y repetir esa aritmética
                // aquí sería un segundo algoritmo que podría discrepar.
                isInScale: frame.allows(Pitch(unchecked: pitchClass)),
                isRoot: root == frame.root
            )
        }
    }

    /// La línea de estado del handoff: `Scale · <nombre>   Root · <nota>`.
    ///
    /// El nombre de la escala en inglés y sin traducir (NFR7).
    public var statusLine: String {
        "Scale · \(Self.name(of: frame.scale))   Root · \(frame.root)"
    }

    static func name(of scale: Scale) -> String {
        switch scale {
        case .minor: "Minor"
        case .major: "Major"
        case .dorian: "Dorian"
        case .phrygian: "Phrygian"
        case .pentatonic: "Pentatonic"
        }
    }
}
