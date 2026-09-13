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

extension TonalFrame {

    /// Los grados del marco que tienen altura en 0–127.
    ///
    /// Es el borde contra el que frenan Pitch y Harmony, y contra el que se
    /// acota lo que suena.
    var midiDegrees: ClosedRange<Int> {
        degree(of: nearest(to: Pitch(unchecked: Pitch.validRange.lowerBound)))!...degree(
            of: nearest(to: Pitch(unchecked: Pitch.validRange.upperBound)))!
    }
}

extension PitchPool {

    /// El grado del pitch en esa posición, contando desde la altura del marco
    /// más cercana, o `nil` fuera del pool.
    ///
    /// **Una altura fuera del marco cuenta desde la más cercana**, con el
    /// desempate de `TonalFrame.nearest(to:)`. Los pads no pueden meterla, pero
    /// un proyecto guardado sí puede traerla.
    func degree(at index: Int, in frame: TonalFrame) -> Int? {
        pitch(at: index).flatMap { frame.degree(of: frame.nearest(to: $0)) }
    }

    /// Lo que suena: cada altura movida su offset de Harmony más el de Pitch,
    /// en grados del marco.
    ///
    /// **Sin Pitch ni Harmony devuelve el pool tal cual**, también si trae
    /// alturas fuera del marco: el camino nuevo no reencuadra nada que antes no
    /// se reencuadrara, y un Cycle sin transformar suena byte a byte como antes.
    ///
    /// **Lo que no cabe en MIDI se queda en la última altura del marco dentro de
    /// 0–127.** Los knobs se frenan antes (FR6, FR10), pero cambiar Scale
    /// conservando Pitch puede llevar ahí, y el pool que suena no emite nunca
    /// fuera de rango (FR3). Si dos alturas acaban en la misma el pool encoge,
    /// igual que en el reencuadre.
    ///
    /// No es código de tiempo real: se llama al construir un `Cycle`, en el hilo
    /// de control.
    func sounding(pitchOffset: PitchOffset, harmony: Harmony, in frame: TonalFrame) -> PitchPool {
        guard pitchOffset != .zero || !harmony.isClean, !isEmpty else { return self }
        let edges = frame.midiDegrees

        var sounding = PitchPool()
        for index in 0..<count {
            guard let degree = degree(at: index, in: frame) else { continue }
            let moved = degree + harmony.offset(at: index) + pitchOffset.degrees
            guard
                let pitch = frame.pitch(
                    atDegree: min(max(moved, edges.lowerBound), edges.upperBound))
            else { continue }
            sounding = sounding.inserting(pitch)
        }
        return sounding
    }
}

extension Cycle {

    /// El offset que deja un giro de Pitch de `delta` clics, **frenado**.
    ///
    /// Dos frenos, y los dos atómicos (FR5, FR6): el rango de ±28 y que ninguna
    /// altura del pool que suena —con Harmony incluido— salga de 0–127. El giro
    /// se aplica hasta el último valor en el que caben todas, nunca a medias ni
    /// acotando nota a nota — así los intervalos se conservan siempre.
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
        if let fit = pool.pitchOffsetLimits(harmony: harmony, in: frame) {
            limits = max(limits.lowerBound, fit.lowerBound)...min(limits.upperBound, fit.upperBound)
        }

        let target = min(max(current + delta, limits.lowerBound), limits.upperBound)
        guard delta > 0 ? target > current : target < current else { return pitchOffset }
        return PitchOffset(unchecked: target)
    }
}

extension PitchPool {

    /// Entre qué offsets de Pitch caben todas las alturas del pool, ya movidas
    /// por Harmony, en 0–127. `nil` con el pool vacío.
    func pitchOffsetLimits(harmony: Harmony, in frame: TonalFrame) -> ClosedRange<Int>? {
        guard !isEmpty else { return nil }
        var bottom = Int.max
        var top = Int.min
        for index in 0..<count {
            guard let degree = degree(at: index, in: frame) else { continue }
            bottom = min(bottom, degree + harmony.offset(at: index))
            top = max(top, degree + harmony.offset(at: index))
        }
        let edges = frame.midiDegrees
        return (edges.lowerBound - bottom)...(edges.upperBound - top)
    }
}
