/// El estado de Harmony de un Cycle: cuántos grados se ha movido cada pitch del
/// pool, y cuál se intenta mover primero en el siguiente clic.
///
/// **El índice del pool es la identidad.** El pool está ordenado de grave a
/// agudo y Harmony no deja cruzar ni chocar, así que el pitch *i* sigue siendo
/// el *i*-ésimo después de cualquier movimiento (`pitch-harmony_20260912`).
///
/// **Es estado, no un valor de knob.** Dos historias de giros con el mismo neto
/// pueden dejar estados distintos —eso es la histéresis—, así que lo que se
/// guarda con el Cycle son los offsets y el cursor, no un número.
///
/// **Ocho huecos de ocho bits en un entero, como `PitchPool`**, y por la misma
/// razón: `Cycle` se copia en el hilo del scheduler y un `Array` metería
/// `retain`/`release` ahí. Un `Int8` por hueco basta: ningún pitch puede
/// alejarse más de 127 grados sin salir de MIDI.
public struct Harmony: Equatable, Sendable {

    /// Sin movimientos: todos los offsets a 0 y el cursor en el primero.
    public static let clean = Harmony(slots: 0, storedCursor: 0)

    /// Ocho offsets con signo, del hueco 0 al 7, cada uno en su byte.
    private let slots: UInt64

    private let storedCursor: UInt8

    private init(slots: UInt64, storedCursor: UInt8) {
        self.slots = slots
        self.storedCursor = storedCursor
    }

    /// El pitch del pool que el siguiente clic intenta mover primero.
    public var cursor: Int { Int(storedCursor) }

    /// Si no hay ningún movimiento ni el cursor se ha desplazado.
    public var isClean: Bool { self == .clean }

    /// Cuántos grados se ha movido el pitch en esa posición del pool. Fuera del
    /// pool, 0.
    ///
    /// Realtime: consultable desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func offset(at index: Int) -> Int {
        guard index >= 0, index < PitchPool.capacity else { return 0 }
        return Int(Int8(truncatingIfNeeded: slots >> UInt64(index * 8)))
    }

    /// El mismo estado con otro offset en esa posición.
    ///
    /// Interno: quien mueve pitches es el paso de Harmony, que valida.
    func with(offset: Int, at index: Int) -> Harmony {
        guard index >= 0, index < PitchPool.capacity else { return self }
        let shift = UInt64(index * 8)
        let byte = UInt64(UInt8(bitPattern: Int8(clamping: offset)))
        return Harmony(
            slots: (slots & ~(0xFF << shift)) | (byte << shift), storedCursor: storedCursor)
    }

    /// El mismo estado con el cursor en otra posición.
    func with(cursor: Int) -> Harmony {
        Harmony(slots: slots, storedCursor: UInt8(clamping: cursor))
    }
}

extension Cycle {

    /// El estado de Harmony tras `delta` clics: **un paso por clic**, en el
    /// sentido del signo (FR8).
    ///
    /// Cada paso intenta primero el pitch del cursor y después los siguientes en
    /// orden circular (FR9). El primero que puede moverse un grado se mueve, y
    /// el cursor queda en el de detrás. Si ninguno puede, ese paso no cambia
    /// nada — ni el cursor.
    ///
    /// **Un movimiento vale si lo que suena después, con Pitch aplicado, cae en
    /// 0–127 y estrictamente entre sus dos vecinos** (FR10). Estrictamente
    /// excluye a la vez el choque y el cruce, y es lo que mantiene el pool
    /// ordenado: el pitch *i* sigue siendo el *i*-ésimo.
    ///
    /// **Con histéresis** (FR11): invertir el sentido es un paso más sobre el
    /// cursor que haya, no deshacer el anterior. Con menos de dos pitches no
    /// hay nada que mover (FR12).
    ///
    /// Se mide en grados y sin acotar al borde de MIDI, que es lo que decide si
    /// un movimiento cabe. No es código de tiempo real.
    func harmonyMoved(by delta: Int) -> Harmony {
        let count = pool.count
        guard count >= 2, delta != 0 else { return harmony }

        let direction = delta > 0 ? 1 : -1
        let edges = frame.midiDegrees
        var state = harmony

        func degree(_ index: Int) -> Int? {
            pool.degree(at: index, in: frame).map {
                $0 + state.offset(at: index) + pitchOffset.degrees
            }
        }

        for _ in 0..<abs(delta) {
            steps: for attempt in 0..<count {
                let index = (state.cursor + attempt) % count
                guard let current = degree(index) else { continue }
                let candidate = current + direction

                guard edges.contains(candidate) else { continue }
                if index > 0, let below = degree(index - 1), candidate <= below { continue }
                if index < count - 1, let above = degree(index + 1), candidate >= above {
                    continue
                }

                state = state.with(offset: state.offset(at: index) + direction, at: index)
                    .with(cursor: (index + 1) % count)
                break steps
            }
        }
        return state
    }
}
