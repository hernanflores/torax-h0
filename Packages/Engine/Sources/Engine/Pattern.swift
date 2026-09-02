/// Los dieciséis Tracks que suenan juntos.
///
/// **Es el valor que cruza al hilo del scheduler.** Hasta la v1 lo publicado era
/// un `Track`; a partir de la v2 son dieciséis, y todo lo que este tipo hace
/// —cómo guarda, cómo se lee y cómo se sustituye un Track— está decidido por esa
/// única exigencia: tiene que ser un dato trivial, copiable con un `memcpy`
/// desde un hilo de tiempo real. `_isPOD(Pattern.self)` es la red que lo vigila.
///
/// **El nombre es el de la Pre Spec**, que llama Pattern al conjunto de los
/// dieciséis Tracks que se reproducen a la vez. Que todavía no se pueda tener
/// más de uno —ni Banks, ni Project— es una limitación de alcance, no otro
/// concepto: cuando lleguen, este tipo ya se llama como se tiene que llamar.
///
/// **Los dieciséis existen siempre y arrancan vacíos.** No hay Tracks que crear
/// ni destruir: un Track sin pool dispara sus Pulses y no tiene material que
/// emitir, así que el silencio sale del material y no de una bandera de
/// actividad que habría que mantener coherente. Es también lo que mantiene el
/// tamaño fijo, porque una colección variable exige asignación y asignar en el
/// camino del scheduler está prohibido.
///
/// > **Estado intermedio del 2026-09-02.** Lo que este tipo guarda ya no se
/// > llama `Track` sino `Cycle`, y de momento hay **uno por Track**: el
/// > renombrado va en su propio commit y el nivel nuevo llega en el siguiente.
/// > `track(at:)` conserva el nombre a propósito —sigue devolviendo lo que ese
/// > Track está tocando— para que la tarea que mete el nivel solo tenga que
/// > cambiar el tipo que devuelve, y no todas las llamadas.
public struct Pattern: Equatable, Sendable {

    /// Cuántos Tracks suenan juntos. La Pre Spec: «hasta 16 Tracks por Pattern».
    public static let trackCount = 16

    /// Dieciséis Tracks seguidos, sin cabecera ni indirección.
    ///
    /// **Una tupla y no un `Array`**, por la misma razón que `PitchPool` guarda
    /// sus ocho alturas en un entero: un `Array` metería conteo de referencias
    /// en un valor que se copia dentro del hilo del scheduler. Y no
    /// `InlineArray`, que resolvería esto de forma legible, porque exige una
    /// versión de plataforma muy posterior al objetivo de despliegue (iOS 17).
    ///
    /// Se lee con aritmética de punteros sobre su almacenamiento —contiguo por
    /// ser homogénea— en vez de con un `switch` de dieciséis casos: el `switch`
    /// no sería más seguro, solo más largo, y habría que escribirlo dos veces.
    /// Los tests recorren los dieciséis huecos, así que un cambio de disposición
    /// se vería inmediatamente.
    private var tracks:
        (
            Track, Track, Track, Track, Track, Track, Track, Track,
            Track, Track, Track, Track, Track, Track, Track, Track
        )

    /// El Cycle de un hueco sin usar: dispara, y no tiene nada que emitir.
    ///
    /// **El silencio sale del pool vacío, no del Shape.** Los Pulses no pueden
    /// ser cero —la Pre Spec los define de 1 a Steps— así que un Track sin
    /// material no se expresa apagando el ritmo, sino no dándole alturas. Es el
    /// mismo estado que `PitchPool()` ya documenta como válido.
    ///
    /// Steps 16 y Pulses 1 son literales dentro de rango, así que el
    /// desempaquetado no puede fallar.
    static let emptyCycle = Cycle(shape: Shape(steps: Steps(16)!, pulses: Pulses(1)!))

    /// Dieciséis Tracks vacíos, **cada uno en su canal**: el Track N emite por
    /// el canal N.
    ///
    /// Dieciséis Tracks y dieciséis canales es la correspondencia que no hay que
    /// explicar, y sin ella los dieciséis sonarían al mismo instrumento. Se puede
    /// cambiar: dos capas rítmicas sobre el mismo sinte es un caso real.
    public init() {
        func empty(_ number: Int) -> Track {
            Track(Self.emptyCycle.on(Channel(unchecked: number)))
        }
        tracks = (
            empty(1), empty(2), empty(3), empty(4),
            empty(5), empty(6), empty(7), empty(8),
            empty(9), empty(10), empty(11), empty(12),
            empty(13), empty(14), empty(15), empty(16)
        )
    }

    /// El Pattern con el que arranca la app: material **solo en el Track 1**.
    ///
    /// **Una rebanada de motor no debería cambiar lo que se oye.** Al pasar de
    /// un Track a dieciséis, la app suena exactamente como sonaba —16/5 sobre
    /// una sola altura— hasta que alguien use los otros quince. El silencio de
    /// esos quince sale de su pool vacío, no de un Shape apagado.
    ///
    /// El material es el que la app ya traía: Steps 16 y Pulses 5, que es uno de
    /// los casos de la Pre Spec y se reconoce de oído, sobre un pool de una sola
    /// altura, que la Pre Spec describe como «centro estable». Arrancar con el
    /// pool vacío también sería legítimo, pero la app abriría muda y averiguar
    /// que hay que pulsar un pad no es algo que la pantalla comunique todavía.
    ///
    /// Los literales están dentro de rango, así que el desempaquetado no puede
    /// fallar.
    public static let initial = Pattern().replacing(
        Cycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: PitchPool().inserting(Pitch(48)!)
        ),
        at: 0
    )

    /// El Track de esa posición, o `nil` fuera de 0–15.
    ///
    /// Fuera de rango devuelve `nil` con el mismo criterio que un pad fuera de la
    /// superficie: no es un error y no revienta.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func track(at index: Int) -> Track? {
        guard (0..<Self.trackCount).contains(index) else { return nil }
        return withUnsafePointer(to: tracks) { pointer in
            pointer.withMemoryRebound(to: Track.self, capacity: Self.trackCount) {
                $0[index]
            }
        }
    }

    /// El Cycle que está sonando en esa posición, o `nil` fuera de 0–15.
    ///
    /// **Es lo que quiere casi todo el mundo.** El scheduler, el emisor y la
    /// pantalla preguntan por el material vigente, no por el contenedor: pedir
    /// `track(at:)?.current` en cada sitio sería repetir la misma frase
    /// cincuenta veces y dejar que alguien la escriba mal una.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func cycle(at index: Int) -> Cycle? {
        track(at: index)?.current
    }

    /// El Pattern con ese Track en esa posición y los otros quince intactos.
    ///
    /// Fuera de rango devuelve el Pattern tal cual: nada que cambiar.
    public func replacing(_ track: Track, at index: Int) -> Pattern {
        guard (0..<Self.trackCount).contains(index) else { return self }

        var updated = self
        withUnsafeMutablePointer(to: &updated.tracks) { pointer in
            pointer.withMemoryRebound(to: Track.self, capacity: Self.trackCount) {
                $0[index] = track
            }
        }
        return updated
    }

    /// El Pattern con ese Cycle sustituyendo al que suena en esa posición, y
    /// **todo lo demás del Track intacto**: sus otros quince Cycles, cuántos
    /// están activos y por cuál va.
    ///
    /// **Es el camino de la edición.** Girar un knob cambia el material vigente
    /// de un Track, no su estructura. Que exista esta sobrecarga es lo que evita
    /// que cada sitio que edita tenga que reconstruir el Track a mano — que es
    /// exactamente la forma de perder campos en silencio contra la que
    /// `Cycle.applying(_:to:)` ya advierte.
    public func replacing(_ cycle: Cycle, at index: Int) -> Pattern {
        guard let track = track(at: index) else { return self }
        return replacing(track.replacingCurrent(cycle), at: index)
    }

    public static func == (lhs: Pattern, rhs: Pattern) -> Bool {
        for index in 0..<Self.trackCount where lhs.track(at: index) != rhs.track(at: index) {
            return false
        }
        return true
    }
}
