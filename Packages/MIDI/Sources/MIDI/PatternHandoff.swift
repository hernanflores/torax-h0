import Engine

/// Entrega el material —los dieciséis Tracks— al hilo del scheduler sin lock.
///
/// **El problema.** El hilo principal edita el Track; el hilo del scheduler lo
/// lee en cada ventana. Un lock entre ambos bloquearía el camino de timing, que
/// es justo lo que `code_styleguides/swift.md` prohíbe. Y copiar un `Track` son
/// varias palabras de memoria, así que tampoco basta con un atómico: no hay
/// atómico de ese tamaño.
///
/// **La solución: disciplina de ranura, no atomicidad de la copia.** Hay un
/// anillo de `slotCount` Tracks preasignados y un contador de generación
/// atómico que dice cuál está publicado. El escritor nunca escribe la ranura
/// publicada: rellena la siguiente del anillo y solo entonces publica, avanzando
/// el contador. El lector mira el contador, copia esa ranura y vuelve a mirar el
/// contador para comprobar que el escritor no le ha dado alcance.
///
/// **Por qué un anillo y no dos búferes.** Con dos ranuras el escritor alterna
/// entre ellas, así que un lector que se duerma una sola publicación despierta
/// leyendo la ranura que el escritor está reescribiendo. Con cuatro, el escritor
/// tiene que publicar tres veces antes de volver a pisar la ranura que el lector
/// latió, y esa distancia es la que el propio lector verifica.
///
/// **Por qué no hay nada que liberar.** Las ranuras se reservan una vez, al
/// construir, y viven lo que viva el objeto. La alternativa —publicar por
/// intercambio de puntero— obliga a decidir cuándo es seguro liberar el snapshot
/// viejo, que es el problema que resuelven RCU y los hazard pointers. Aquí no
/// existe: no se libera nada.
///
/// **Qué pasa cuando crece el modelo.** El protocolo no depende del tamaño del
/// snapshot: llegaron Tonal y Groove, y en la v2 la ranura pasó de un `Track` a
/// un `Pattern` de dieciséis sin tocar una línea de la disciplina de ranura.
///
/// **Lo que cuesta, medido el 2026-08-31**: `Track` son 112 bytes y `Pattern`
/// 1792, así que el anillo de cuatro ranuras ocupa 7 KB y cada `load()` copia
/// 1,75 KB. Medido en `debug`, un `load()` completo —dos lecturas atómicas, la
/// copia y la comprobación de generación— sale a **274 ns**, contra una ventana
/// de 20 ms: el 0,0014% del presupuesto. No hay nada que decidir aquí, y por eso
/// se copia entero en vez de publicar por Track.
///
/// Lo que sí cambia es la aritmética del riesgo: copiar dieciséis veces más deja
/// al lector expuesto más tiempo, y por eso el test de concurrencia publica un
/// Pattern con los dieciséis Tracks correlacionados, no solo con sus campos.
/// Lo que sí hay que preservar es que `Track` siga siendo un tipo trivial —sin
/// `Array` ni nada con conteo de referencias—, porque copiarlo ocurre en el hilo
/// del scheduler y un `retain` ahí es una violación de las reglas de tiempo
/// real. Hay un test que lo vigila.
public final class PatternHandoff: @unchecked Sendable {

    /// Ranuras del anillo. Potencia de dos para indexar con una máscara en vez
    /// de con un módulo, que es una división.
    private static let slotCount = 4
    private static let slotMask = UInt64(slotCount - 1)

    /// Distancia máxima que el contador puede haber avanzado sin que la ranura
    /// leída haya podido reescribirse.
    ///
    /// La ranura de la generación `g` se vuelve a escribir cuando el escritor
    /// prepara la generación `g + slotCount`, y **empieza a escribirla antes** de
    /// publicar ese número. Así que ya es sospechosa cuando el contador llega a
    /// `g + slotCount - 1`: el margen seguro es estrictamente menor que eso.
    private static let safeGenerationDistance = UInt64(slotCount - 1)

    private let slots: UnsafeMutablePointer<Pattern>

    /// Generación publicada. Monótona: solo avanza.
    ///
    /// `AtomicCounter` ya hace `store` con release y `load` con acquire, que es
    /// exactamente el emparejamiento que este protocolo necesita: el release del
    /// escritor publica la escritura de la ranura, y el acquire del lector la
    /// hace visible.
    private let generation = AtomicCounter(0)

    public init(_ initial: Pattern) {
        slots = .allocate(capacity: Self.slotCount)
        slots.initialize(repeating: initial, count: Self.slotCount)
    }

    /// Arranca con un solo Track en la primera posición y quince vacíos.
    ///
    /// > **Puente de la v2, fase 2.** Existe mientras haya quien todavía piense
    /// > en un Track solo —la interfaz y buena parte de los tests—. La fase 4 lo
    /// > retira: para entonces todo el mundo publica un Pattern.
    public convenience init(_ initial: Track) {
        self.init(Pattern().replacing(initial, at: 0))
    }

    deinit {
        slots.deinitialize(count: Self.slotCount)
        slots.deallocate()
    }

    /// Publica material nuevo: los dieciséis Tracks a la vez.
    ///
    /// **Un solo escritor.** Lo llama el hilo principal, que es el único que muta
    /// el estado de edición (`code_styleguides/swift.md`). No es código de tiempo
    /// real y no necesita serlo: publicar es un gesto de usuario.
    public func publish(_ pattern: Pattern) {
        let next = generation.value &+ 1
        slots[Int(next & Self.slotMask)] = pattern
        generation.value = next
    }

    /// Devuelve el material publicado, o `nil` si la lectura hay que descartarla.
    ///
    /// **`nil` no es un error:** significa que el escritor dio la vuelta al
    /// anillo mientras se copiaba la ranura, así que el valor copiado podría
    /// mezclar dos publicaciones. Quien llama conserva el material que ya tenía y
    /// vuelve a intentarlo en la ventana siguiente, unos milisegundos después.
    /// Preferir eso a reintentar aquí es deliberado: un bucle de reintento en el
    /// hilo del scheduler no tiene cota superior, y perder una actualización
    /// durante una ventana es inaudible.
    ///
    /// En la práctica no ocurre. Publicar es un giro de knob y leer pasa una vez
    /// por ventana; harían falta cuatro publicaciones dentro del tiempo de copiar
    /// una estructura de enteros.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public func load() -> Pattern? {
        let before = generation.value
        let pattern = slots[Int(before & Self.slotMask)]
        let after = generation.value

        guard Self.readIsSafe(latched: before, observed: after) else { return nil }
        return pattern
    }

    /// Decide si una lectura es fiable, dadas las generaciones vistas antes y
    /// después de copiar la ranura.
    ///
    /// Está separado de `load()` porque la rama que descarta es, por diseño,
    /// prácticamente inalcanzable en ejecución real —hace falta que el escritor
    /// dé la vuelta al anillo dentro del tiempo de copiar unos enteros—, y una
    /// rama que no se puede provocar es una rama que no se puede testear. Aquí
    /// sí se comprueba, sobre los números.
    ///
    /// La resta es envolvente a propósito: el contador es monótono pero de 64
    /// bits, y `&-` da la distancia correcta también si diera la vuelta.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    static func readIsSafe(latched: UInt64, observed: UInt64) -> Bool {
        observed &- latched < safeGenerationDistance
    }
}
