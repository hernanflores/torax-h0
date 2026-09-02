/// Las alturas que un Track puede usar. Hasta ocho.
///
/// **Es un pool, no una melodía.** La Pre Spec: `PITCH` determina el *pool* de
/// notas que un Track puede usar, no escribe una línea fija. Aquí no hay
/// asignación de altura a posición, y no debe haberla: mostrar una nota por paso
/// es un antipatrón declarado en `product-guidelines.md` porque sugiere que las
/// alturas están clavadas a Steps.
///
/// **Ocho huecos de ocho bits en un entero, no un `Array`.** No es una
/// optimización: `Cycle` se copia en el hilo del scheduler y un `Array` metería
/// `retain`/`release` ahí, que las reglas de tiempo real prohíben.
/// `tech-stack.md` lo dejó escrito antes de que hiciera falta —«el pool de
/// pitches tiene que ser almacenamiento inline de 8 huecos»— y
/// `_isPOD(Cycle.self)` es la red que lo vigila.
///
/// Que quepa en 64 bits es la misma coincidencia deliberada que en
/// `EuclideanRhythm`: una altura MIDI son siete bits, así que ocho caben en ocho
/// bytes con un valor de sobra para marcar el hueco vacío.
///
/// **Ordenado de grave a agudo.** El recorrido del pool es el arpegio ascendente
/// que la Pre Spec describe para Style monofónico, y ordenar aquí hace que no
/// dependa del orden en que se pulsaron los pads. Dos pools con las mismas notas
/// son el mismo pool.
public struct PitchPool: Equatable, Sendable {

    /// Cuántas alturas caben. La Pre Spec: «hasta 8 pitches».
    public static let capacity = 8

    /// Marca de hueco vacío. `0x7F` es la altura 127, que es válida, así que el
    /// centinela tiene que caer fuera del rango MIDI.
    private static let empty: UInt8 = 0xFF

    /// Ocho huecos de un byte, del más grave al más agudo, seguidos de vacíos.
    private var slots: UInt64

    /// Cuántas alturas hay.
    public private(set) var count: Int

    public var isEmpty: Bool { count == 0 }

    /// Pool vacío. Es un estado válido: el Track dispara sus Pulses y no tiene
    /// material que emitir.
    public init() {
        slots = .max  // los ocho bytes a `empty`
        count = 0
    }

    /// La altura en la posición dada, o `nil` fuera del pool.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func pitch(at index: Int) -> Pitch? {
        guard index >= 0, index < count else { return nil }
        return Pitch(unchecked: Int(byte(at: index)))
    }

    /// Si la altura está en el pool.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func contains(_ pitch: Pitch) -> Bool {
        for index in 0..<count where Int(byte(at: index)) == pitch.value { return true }
        return false
    }

    /// Añade una altura, manteniendo el orden.
    ///
    /// **Insertar en un pool lleno no cambia nada.** Hacer sitio tirando una
    /// nota sería destruir material, que `product-guidelines.md` prohíbe; que no
    /// entre es un límite, y un límite se comunica no haciendo nada.
    ///
    /// Insertar una altura ya presente tampoco cambia nada: el pool es un
    /// conjunto.
    public func inserting(_ pitch: Pitch) -> PitchPool {
        guard count < Self.capacity, !contains(pitch) else { return self }

        var updated = self
        var position = 0
        while position < count, Int(byte(at: position)) < pitch.value { position += 1 }

        // Desplaza desde el final para no pisar lo que aún no se ha movido.
        var index = count
        while index > position {
            updated.setByte(updated.byte(at: index - 1), at: index)
            index -= 1
        }
        updated.setByte(UInt8(pitch.value), at: position)
        updated.count += 1
        return updated
    }

    /// Quita una altura. Si no estaba, no cambia nada.
    public func removing(_ pitch: Pitch) -> PitchPool {
        guard let position = position(of: pitch) else { return self }

        var updated = self
        for index in position..<(count - 1) {
            updated.setByte(updated.byte(at: index + 1), at: index)
        }
        updated.setByte(Self.empty, at: count - 1)
        updated.count -= 1
        return updated
    }

    /// Mete la altura si no estaba, la saca si estaba.
    ///
    /// Es lo que hace un pad: la Pre Spec dice que una nota activada entra al
    /// pool y una desactivada se excluye, con el mismo botón.
    public func toggling(_ pitch: Pitch) -> PitchPool {
        contains(pitch) ? removing(pitch) : inserting(pitch)
    }

    /// Reubica dentro del marco las alturas que hayan quedado fuera.
    ///
    /// **Reencuadra, no vacía.** Es la regla de destructividad de
    /// `product-guidelines.md` —«el pool tonal sobrevive a un cambio de Scale
    /// reencuadrándose, no vaciándose»—, la misma que rige a `Pulses` desde la
    /// rebanada 2.
    ///
    /// **Con una pérdida aceptada y fijada por un test:** si dos alturas caen en
    /// la misma al reubicarse, el pool encoge. Guardar el duplicado sería peor
    /// —el arpegio repetiría una nota sin que nadie lo pidiera— y elegir otra
    /// distinta sería inventar material que el usuario no puso.
    public func reframed(to frame: TonalFrame) -> PitchPool {
        var reframed = PitchPool()
        for index in 0..<count {
            guard let pitch = pitch(at: index) else { break }
            reframed = reframed.inserting(frame.nearest(to: pitch))
        }
        return reframed
    }

    // MARK: - Los huecos

    private func byte(at index: Int) -> UInt8 {
        UInt8(truncatingIfNeeded: slots >> UInt64(index * 8))
    }

    private mutating func setByte(_ value: UInt8, at index: Int) {
        let shift = UInt64(index * 8)
        slots = (slots & ~(0xFF << shift)) | (UInt64(value) << shift)
    }

    private func position(of pitch: Pitch) -> Int? {
        for index in 0..<count where Int(byte(at: index)) == pitch.value { return index }
        return nil
    }
}
