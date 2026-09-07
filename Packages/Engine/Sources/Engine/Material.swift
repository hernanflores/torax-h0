/// Si un Pattern, un Bank o un Project tienen algo que suene.
///
/// **El criterio ya existía y no se inventa otro aquí.** `TransportModel` lo
/// escribía desde la pantalla del handoff: un Pattern tiene material si **alguno
/// de sus doce Tracks tiene pool**. Lo que cambia el 2026-09-07 es dónde vive
/// —baja a `Engine`, que es donde hay tests— y que ahora hay 256 Patterns a los
/// que preguntárselo en vez de uno.
///
/// **Por qué el pool y no el Shape.** Un Track sin pool dispara sus Pulses y no
/// tiene alturas que emitir, así que es silencio; y los Pulses no pueden ser
/// cero, porque la Pre Spec los define de 1 a Steps. El silencio sale del
/// material y no de una bandera de actividad — la decisión está tomada desde
/// `Pattern.emptyCycle` y esto solo la lee.
///
/// **Es una lectura, no un contador.** Nadie mantiene estos números: borrar un
/// Pattern baja la cuenta porque la cuenta se calcula, y así no hay dos fuentes
/// de verdad que puedan discrepar.
extension Pattern {

    /// Si alguno de los doce Tracks tiene alturas que emitir.
    ///
    /// Mira el **Cycle en edición**, que es el criterio que ya usaba la pantalla:
    /// lo que se está construyendo es lo que cuenta como material, aunque suene
    /// otro.
    public var hasMaterial: Bool {
        (0..<Self.trackCount).contains { !(editingCycle(at: $0)?.pool.isEmpty ?? true) }
    }
}

extension Bank {

    /// Cuántos de los dieciséis tienen material.
    ///
    /// **Cuenta contenido, no huecos.** Es la regla que `BankGrid` ya lleva
    /// escrita: decir «16 patterns» con quince vacíos sería contar sitios y
    /// llamarlos contenido.
    public var patternsWithMaterial: Int {
        patternsHavingMaterial.filter { $0 }.count
    }

    /// Cuáles, en orden. Es lo que la rejilla necesita para pintar cada hueco sin
    /// preguntar dieciséis veces.
    public var patternsHavingMaterial: [Bool] {
        (0..<Self.patternCount).map { pattern(at: $0)?.hasMaterial ?? false }
    }

    /// Si el Bank tiene algo, en cualquiera de sus dieciséis.
    public var hasMaterial: Bool { patternsHavingMaterial.contains(true) }
}

extension Project {

    /// Cuántos de los dieciséis Banks tienen algo.
    public var banksWithMaterial: Int {
        (0..<Self.bankCount).filter { bank(at: $0)?.hasMaterial ?? false }.count
    }
}
