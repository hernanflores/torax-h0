/// Dieciséis Patterns y un tempo propio.
///
/// **El nivel que la Pre Spec pone encima del Pattern**: «Bank: contenedor
/// musical de alto nivel (canción, setup o sección de live). Tiene 16 Patterns y
/// tempo propio». Es lo que permite tener un groove principal, un break y un
/// fill sin reconstruirlos a mano cada vez.
///
/// **No es un dato de tiempo real, y por eso no se parece a `Pattern`.** Lo que
/// cruza al hilo del scheduler es un `Pattern` —2304 bytes por Cycle activo,
/// copiado en cada ventana— y por eso aquél guarda sus Tracks en una tupla
/// inline, sin nada con conteo de referencias dentro. El Bank **no se copia ahí
/// nunca**: se elige un Pattern en el hilo principal y se publica ese. Así que
/// guarda los dieciséis en un `Array`, que es lo que corresponde a un valor que
/// vive donde se puede asignar. Una tupla de dieciséis Patterns serían unos
/// 592 KB moviéndose por la pila sin que nadie lo haya pedido.
///
/// `BankTests.testTheBankIsNotTrivialAndThePatternStillIs` afirma las dos cosas
/// juntas, porque lo que hay que preservar es la relación: **la restricción de
/// tiempo real no sube de nivel**.
///
/// **Los dieciséis existen siempre y arrancan vacíos**, como los doce Tracks del
/// `Pattern` y los dieciséis Cycles del `Track`. No hay Patterns que crear ni
/// destruir: elegir uno no puede fallar, no asigna y no tiene caso de error. Un
/// Pattern vacío es un `Pattern()` —doce Tracks sin pool, que disparan y no
/// tienen material que emitir—, así que el silencio sale del material y no de
/// una bandera de actividad que habría que mantener coherente.
public struct Bank: Equatable, Sendable {

    /// Cuántos Patterns tiene un Bank. La Pre Spec: «16 Patterns por Bank».
    ///
    /// **Es el único sitio donde el número se escribe.** De él derivan la
    /// rejilla de la pantalla, el recorrido del guardado y los índices que se
    /// acotan.
    public static let patternCount = 16

    /// El tempo con el que arranca un Bank nuevo, y con el que la app arranca
    /// desde la rebanada 1.
    public static let defaultTempo = Tempo(beatsPerMinute: 120)!

    /// Los dieciséis, siempre presentes.
    private var patterns: [Pattern]

    /// El tempo de este Bank.
    ///
    /// **Manda solo con el reloj interno.** Con la fuente en `External` el tempo
    /// lo pone el maestro y cambiar de Bank no lo toca; el valor guardado no
    /// desaparece, vuelve a mandar en cuanto la fuente sea `Internal`. Lo decide
    /// quien selecciona el Bank, no este tipo.
    public let tempo: Tempo

    /// Un Bank vacío a 120 BPM.
    public init() {
        patterns = Array(repeating: Pattern(), count: Self.patternCount)
        tempo = Self.defaultTempo
    }

    /// El constructor completo, interno a propósito: fuera se llega por
    /// `replacing(_:at:)` y `withTempo(_:)`, que son los que garantizan que
    /// siguen siendo dieciséis.
    init(patterns: [Pattern], tempo: Tempo) {
        precondition(patterns.count == Self.patternCount)
        self.patterns = patterns
        self.tempo = tempo
    }

    /// El Pattern de esa posición, o `nil` fuera de 0–15.
    ///
    /// Fuera de rango devuelve `nil` con el mismo criterio que
    /// `Pattern.track(at:)`: no es un error y no revienta.
    public func pattern(at index: Int) -> Pattern? {
        guard (0..<Self.patternCount).contains(index) else { return nil }
        return patterns[index]
    }

    /// El Bank con ese Pattern en esa posición y los otros quince intactos.
    ///
    /// Fuera de rango devuelve el Bank tal cual: nada que cambiar.
    public func replacing(_ pattern: Pattern, at index: Int) -> Bank {
        guard (0..<Self.patternCount).contains(index) else { return self }

        var updated = patterns
        updated[index] = pattern
        return Bank(patterns: updated, tempo: tempo)
    }

    /// El mismo Bank a otro tempo, con sus dieciséis Patterns intactos.
    public func withTempo(_ tempo: Tempo) -> Bank {
        Bank(patterns: patterns, tempo: tempo)
    }
}
