/// Generador pseudoaleatorio sembrado.
///
/// **`tech-stack.md` lo exige desde el primer commit**: «El aleatorio es
/// pseudoaleatorio con semilla … PRNG explícito y sembrado, nunca
/// `Int.random()`». La Pre Spec pone la razón musical: la secuencia tiene que
/// «cambiar, pero no ser caos totalmente impredecible». Probability es su primer
/// usuario.
///
/// **Qué significa repetible aquí.** El generador avanza por Pulse, así que dos
/// vueltas consecutivas del anillo no deciden lo mismo. Lo que se repite es la
/// sesión: resembrarlo con la misma semilla reproduce exactamente la misma
/// secuencia. Precisión documentada con fecha en `tech-stack.md` el 2026-08-29.
///
/// **Por qué no se usa `SystemRandomNumberGenerator` ni `RandomNumberGenerator`
/// de la stdlib.** El protocolo obligaría a pasar el generador como
/// `inout some RandomNumberGenerator`, y usarlo como existencial metería boxing
/// en el hilo del scheduler. Este tipo es un `struct` concreto y trivial: su
/// estado son ocho bytes que se copian sin tocar el conteo de referencias.
///
/// El algoritmo es *xorshift64\**: tres desplazamientos, tres XOR y una
/// multiplicación. Se elige por ser suficiente para decidir omisiones y caber
/// entero en el camino de tiempo real — no es criptográfico y no pretende
/// serlo.
public struct SeededRandom: Equatable, Sendable {

    /// Semilla por defecto del producto.
    ///
    /// Fija a propósito: es lo que hace que pulsar Play dos veces reproduzca la
    /// misma secuencia de omisiones. Un valor sembrado del reloj daría una
    /// sesión distinta cada vez y rompería la reproducibilidad que la Pre Spec
    /// pide.
    public static let defaultSeed: UInt64 = 0x2545_F491_4F6C_DD1D

    /// Estado del generador. Nunca es cero: ver el inicializador.
    private var state: UInt64

    /// - Parameter seed: cualquier valor. El cero se sustituye por una
    ///   constante, porque *xorshift* con estado cero se queda clavado en cero
    ///   para siempre — es el modo de fallo clásico de la familia, y se cierra
    ///   aquí en vez de confiar en que nadie siembre con cero.
    public init(seed: UInt64 = SeededRandom.defaultSeed) {
        state = seed == 0 ? SeededRandom.defaultSeed : seed
    }

    /// El siguiente valor de la secuencia.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Generates the next pseudo-random value in the sequence.
    /// - Returns: The next `UInt64` value.
    public mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}
