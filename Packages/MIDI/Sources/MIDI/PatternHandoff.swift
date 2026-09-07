import Engine

/// Entrega el material —los dieciséis Tracks— al hilo del scheduler sin lock.
///
/// **El problema.** El hilo principal edita el Track; el hilo del scheduler lo
/// lee en cada ventana. Un lock entre ambos bloquearía el camino de timing, que
/// es justo lo que `code_styleguides/swift.md` prohíbe. Y copiar un `Cycle` son
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
/// **Lo que cuesta, medido el 2026-08-31**: `Track` son 144 bytes y `Pattern`
/// 2304, así que el anillo de cuatro ranuras ocupa 9 KB y cada `load()` copia
/// 2,25 KB. Medido en `debug` con el Track de 112 bytes —antes de que se le
/// añadiera el marco tonal—, un `load()` completo salía a **274 ns** contra una
/// ventana de 20 ms: el 0,0014% del presupuesto. Un 28% más de bytes no cambia
/// el orden de magnitud. No hay nada que decidir aquí, y por eso se copia entero
/// en vez de publicar por Track.
///
/// **Y lo que costaría con Cycles, medido el 2026-09-02, antes de construirlo.**
/// Cuando el Track contenga dieciséis Cycles, el snapshot pasa a **36 992 bytes**
/// —256 Cycles más dos contadores por Track— y el anillo de cuatro ranuras a
/// **147 968 bytes**, reservados una vez al construir. En la misma pasada y en la
/// misma máquina, en `debug`:
///
/// | | tamaño | `load()` | % de la ventana de 20 ms |
/// |---|---|---|---|
/// | Hoy | 2304 B | ~125 ns | 0,0006% |
/// | Con Cycles | 36 992 B | ~870 ns | **0,0044%** |
///
/// Dieciséis veces más bytes cuestan **siete** veces más tiempo, no dieciséis:
/// una copia grande amortiza mejor que una pequeña. El presupuesto que la Fase 1
/// del track `cycles_20260901` puso delante de la decisión era el 1% de la
/// ventana; el número está tres órdenes de magnitud por debajo, así que se copia
/// el Pattern entero por ventana y el Cycle avanza en el hilo del scheduler, tal
/// como estaba diseñado. Los tests que producen estas cifras están en
/// `CycleSnapshotCostTests`.
///
/// Lo que sí cambia es la aritmética del riesgo: copiar dieciséis veces más deja
/// al lector expuesto más tiempo, y por eso el test de concurrencia publica un
/// Pattern con los dieciséis Tracks correlacionados, no solo con sus campos.
/// Lo que sí hay que preservar es que `Cycle` siga siendo un tipo trivial —sin
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

    /// El Pattern que espera al límite de compás.
    ///
    /// **Una ranura y no otro anillo.** Solo hay un pendiente a la vez —armar dos
    /// veces deja el último, que es lo que un directo pide— y lo escribe el hilo
    /// principal mientras el del scheduler lo mira una vez por ventana. Medido
    /// antes de construirlo: la comprobación cuesta menos que el ruido de la
    /// medición, 0,0232% de la ventana (`ArmedSlotCostTests`).
    private let armedSlot: UnsafeMutablePointer<Pattern>

    /// Generación de lo armado. **Impar significa «hay algo pendiente»**, par
    /// «no hay nada».
    ///
    /// La paridad evita un opcional en el camino de tiempo real: comprobar si
    /// hay pendiente es leer un entero y mirar un bit, sin ramas que asignen. Y
    /// como el contador solo avanza, armar dos veces sin adoptar deja el último
    /// sin que nadie tenga que limpiar nada.
    private let armedGeneration = AtomicCounter(0)

    /// Generación publicada. Monótona: solo avanza.
    ///
    /// `AtomicCounter` ya hace `store` con release y `load` con acquire, que es
    /// exactamente el emparejamiento que este protocolo necesita: el release del
    /// escritor publica la escritura de la ranura, y el acquire del lector la
    /// hace visible.
    private let generation = AtomicCounter(0)

    #if DEBUG
        /// Cuántas veces se ha leído la ranura publicada.
        ///
        /// **Existe para que «una lectura por ventana» sea comprobable**, que es
        /// la propiedad que la rebanada de Cycles necesita mantener: con 2,25 KB
        /// una lectura de más por evento era invisible; con un snapshot dieciséis
        /// veces mayor es una copia por nota. Sin contador, un retroceso a leer
        /// por evento no lo vería nadie hasta medir jitter en dispositivo.
        ///
        /// **Solo en DEBUG.** En release no se compila ni el incremento, así que
        /// el camino de tiempo real queda exactamente como estaba. El
        /// `fetch_add` que se paga en los tests es una vez por ventana.
        let loadCount = AtomicCounter(0)
    #endif

    public init(_ initial: Pattern) {
        slots = .allocate(capacity: Self.slotCount)
        slots.initialize(repeating: initial, count: Self.slotCount)
        armedSlot = .allocate(capacity: 1)
        armedSlot.initialize(to: initial)
    }

    /// Arranca con un solo Track en la primera posición y quince vacíos.
    ///
    /// > **Puente de la v2, fase 2.** Existe mientras haya quien todavía piense
    /// > en un Track solo —la interfaz y buena parte de los tests—. La fase 4 lo
    /// > retira: para entonces todo el mundo publica un Pattern.
    public convenience init(_ initial: Cycle) {
        self.init(Pattern().replacing(initial, at: 0))
    }

    deinit {
        slots.deinitialize(count: Self.slotCount)
        slots.deallocate()
        armedSlot.deinitialize(count: 1)
        armedSlot.deallocate()
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
        #if DEBUG
            loadCount.increment()
        #endif
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

    // MARK: - El Pattern armado

    /// Deja un Pattern esperando al límite de compás. **No publica**: hasta que
    /// alguien adopte, sigue sonando el de antes.
    ///
    /// **Un solo escritor**, el hilo principal, igual que `publish(_:)`. Armar
    /// es un gesto de usuario y no es código de tiempo real.
    ///
    /// Armar dos veces deja el último: cambiar de idea antes del límite es
    /// normal en directo, y no hay cola porque un Pattern encolado que ya no se
    /// quiere no tiene forma de cancelarse a mitad.
    public func arm(_ pattern: Pattern) {
        armedSlot.pointee = pattern
        armedGeneration.value = armedGeneration.value | 1
    }

    /// Quita lo pendiente sin adoptarlo.
    ///
    /// Existe para Stop (FR10): ahí lo pendiente pasa a vigente por otro camino
    /// —con el transporte parado no hay rejilla que respetar— y no puede quedar
    /// nada armado detrás.
    public func disarm() {
        armedGeneration.value = armedGeneration.value & ~UInt64(1)
    }

    /// Si hay algo esperando.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    public var hasArmedPattern: Bool { armedGeneration.value & 1 == 1 }

    /// Lo que está armado, o lo publicado si no hay nada.
    ///
    /// **Lo lee el hilo principal**, no el del scheduler: existe para que Stop
    /// pueda quedarse con lo pendiente sin volver a leerlo del anillo.
    public var armedPattern: Pattern { armedSlot.pointee }

    /// Publica lo armado, si lo hay. Devuelve si hizo algo.
    ///
    /// **Es lo que el scheduler llama en cada límite de compás**, y casi siempre
    /// sin nada pendiente: por eso el caso vacío es una lectura atómica y una
    /// comparación, y nada más.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    @discardableResult
    public func adoptArmedPattern() -> Bool {
        guard hasArmedPattern else { return false }
        publish(armedSlot.pointee)
        disarm()
        return true
    }

}
