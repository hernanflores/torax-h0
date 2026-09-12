/// Cuántos grados de la escala transpone Pitch el pool de un Cycle.
///
/// **El usuario lee `Pitch`.** El sufijo es desambiguación de Swift frente a
/// `Pitch`, la altura MIDI, no un término nuevo: es el mismo caso que
/// `repeatTime` frente a `MusicalTime` (NFR5 de `pitch-harmony_20260912`).
///
/// **En grados, no en semitonos.** Un grado arriba es siempre la siguiente
/// altura del marco, así que el pool sigue en tonalidad y conserva sus
/// intervalos. La desviación de la Pre Spec está escrita en su nota del
/// 2026-09-12.
///
/// **Un `Int8` y no un `Int`** por la misma razón que `Accent` dentro de
/// `Modulation`: el valor viaja dentro de `Cycle`, que se copia en el hilo del
/// scheduler dieciséis veces por Track. Un byte basta para ±28.
public struct PitchOffset: Equatable, Sendable {

    /// ±28 grados: unas cuatro octavas en una escala de siete notas. Es el
    /// `displacementRange` que Ctrl All usa para su tope.
    public static let validRange: ClosedRange<Int> = -28...28

    /// Sin transposición.
    public static let zero = PitchOffset(unchecked: 0)

    private let stored: Int8

    /// Los grados, con signo.
    public var degrees: Int { Int(stored) }

    /// Devuelve `nil` fuera de ±28.
    public init?(_ degrees: Int) {
        guard Self.validRange.contains(degrees) else { return nil }
        stored = Int8(degrees)
    }

    /// Vía interna para valores ya acotados por construcción.
    init(unchecked degrees: Int) {
        stored = Int8(degrees)
    }
}

extension PitchPool {

    /// El pool con cada altura movida `offset` grados dentro del marco.
    ///
    /// **Con offset 0 devuelve el pool tal cual**, también si trae alturas fuera
    /// del marco: el camino nuevo no reencuadra nada que antes no se
    /// reencuadrara, y un Cycle sin transponer suena byte a byte como antes.
    ///
    /// **Una altura fuera del marco se transpone desde la más cercana**, con el
    /// desempate de `TonalFrame.nearest(to:)`. Los pads no pueden meterla, pero un
    /// proyecto guardado sí puede traerla.
    ///
    /// **Lo que no cabe en MIDI se queda en la última altura del marco dentro de
    /// 0–127.** El knob se frena antes (FR6), pero cambiar Scale conservando
    /// Pitch puede llevar ahí, y el pool que suena no emite nunca fuera de rango
    /// (FR3). Si dos alturas acaban en la misma el pool encoge, igual que en el
    /// reencuadre.
    ///
    /// No es código de tiempo real: se llama al construir un `Cycle`, en el hilo
    /// de control.
    func transposed(by offset: PitchOffset, in frame: TonalFrame) -> PitchPool {
        guard offset != .zero, !isEmpty,
            let lowest = frame.degree(
                of: frame.nearest(to: Pitch(unchecked: Pitch.validRange.lowerBound))),
            let highest = frame.degree(
                of: frame.nearest(to: Pitch(unchecked: Pitch.validRange.upperBound)))
        else { return self }

        var transposed = PitchPool()
        for index in 0..<count {
            guard let pitch = pitch(at: index),
                let degree = frame.degree(of: frame.nearest(to: pitch)),
                let moved = frame.pitch(
                    atDegree: min(max(degree + offset.degrees, lowest), highest))
            else { continue }
            transposed = transposed.inserting(moved)
        }
        return transposed
    }
}

extension Cycle {

    /// El offset que deja un giro de Pitch de `delta` clics, **frenado**.
    ///
    /// Dos frenos, y los dos atómicos (FR5, FR6): el rango de ±28 y que ninguna
    /// altura del pool que suena salga de 0–127. El giro se aplica hasta el
    /// último valor en el que caben todas, nunca a medias ni acotando nota a
    /// nota — así los intervalos se conservan siempre.
    ///
    /// **Desde fuera de los límites solo se puede volver.** Un cambio de Scale
    /// que conserva Pitch puede dejar el offset donde ya no cabe. Girar hacia
    /// fuera no hace nada; girar hacia dentro lleva directamente al último valor
    /// que cabe, que es el primer clic que cambia lo que suena.
    ///
    /// Con el pool vacío solo frena el rango.
    func pitchOffset(movedBy delta: Int) -> PitchOffset {
        let current = pitchOffset.degrees
        var limits = PitchOffset.validRange
        if let fit = pool.pitchOffsetLimits(in: frame) {
            limits = max(limits.lowerBound, fit.lowerBound)...min(limits.upperBound, fit.upperBound)
        }

        let target = min(max(current + delta, limits.lowerBound), limits.upperBound)
        guard delta > 0 ? target > current : target < current else { return pitchOffset }
        return PitchOffset(unchecked: target)
    }
}

extension PitchPool {

    /// Entre qué offsets caben todas las alturas del pool en 0–127, o `nil` con
    /// el pool vacío.
    ///
    /// Una altura fuera del marco cuenta desde la más cercana, igual que en
    /// `transposed(by:in:)`.
    func pitchOffsetLimits(in frame: TonalFrame) -> ClosedRange<Int>? {
        guard !isEmpty,
            let lowest = frame.degree(
                of: frame.nearest(to: Pitch(unchecked: Pitch.validRange.lowerBound))),
            let highest = frame.degree(
                of: frame.nearest(to: Pitch(unchecked: Pitch.validRange.upperBound))),
            let first = pitch(at: 0), let last = pitch(at: count - 1),
            let bottom = frame.degree(of: frame.nearest(to: first)),
            let top = frame.degree(of: frame.nearest(to: last))
        else { return nil }
        return (lowest - bottom)...(highest - top)
    }
}
