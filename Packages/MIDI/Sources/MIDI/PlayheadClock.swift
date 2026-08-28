/// Lleva el origen temporal del scheduler a la interfaz, sin lock.
///
/// **Es el camino que faltaba.** `TrackHandoff` publica del hilo de control al
/// del scheduler; esto va en la dirección contraria, que es la que el playhead
/// necesita. Las reglas son las mismas: el hilo del scheduler no se bloquea, y
/// quien lea tarde —o no lea— no puede afectarle.
///
/// **Por qué basta un atómico y `TrackHandoff` necesitaba un anillo de
/// ranuras.** Un `Track` son varias palabras de memoria y no hay atómico de ese
/// tamaño, así que hizo falta disciplina de ranura. Aquí lo publicado es **un
/// solo entero de 64 bits**, el origen en ticks de host: cabe en el atómico que
/// ya existe y el protocolo desaparece. La asimetría es del dato, no del
/// problema.
///
/// **Por qué se publica el origen y no el Step en curso.** El scheduler trabaja
/// por adelantado: entrega los Steps hasta una ventana de look-ahead antes de
/// que suenen. Publicar el último Step entregado pondría el playhead por delante
/// de lo que se oye. Publicando el origen, la interfaz resta contra el reloj de
/// host y obtiene el instante real; qué Step corresponde a ese instante lo
/// decide `Playhead`, en `Engine`, donde se puede testear.
///
/// **El coste para el scheduler es una escritura, una vez.** El origen se toma
/// al arrancar el bucle y no vuelve a cambiar mientras suene: no hay nada que
/// publicar por Step ni por ventana.
public final class PlayheadClock: @unchecked Sendable {

    /// Origen en ticks de host, o `0` si el transporte no está corriendo.
    ///
    /// **`0` como centinela es seguro aquí porque lo escribimos nosotros.** No
    /// se deduce de que el reloj de host no pueda valer cero: se pone
    /// explícitamente al parar, y solo lo pone `stop()`.
    private let origin = AtomicCounter(0)

    public init() {}

    /// Fija el origen del transporte.
    ///
    /// **Sin test automático, a propósito.** Verificarlo exige correr el bucle
    /// del scheduler, y cada vez que la suite lo arranca una vez más,
    /// `VirtualLoopbackTests` pasa de fallar de forma intermitente a fallar
    /// **3 de 3 pasadas** con `clientCreationFailed(-50)`. Medido el 2026-08-28
    /// contra `main`, que da 0 de 4. La causa pertenece a
    /// `midi-test-flake_20260826`; hasta que se arregle, esta línea se verifica
    /// en dispositivo —el playhead va con lo que suena o no va— y no en la
    /// suite.
    ///
    /// Realtime: llamado desde el hilo del scheduler, una vez al arrancar.
    /// Sin asignaciones, sin locks, sin await.
    func start(atHostTime hostTime: UInt64) {
        origin.value = hostTime
    }

    /// Deja el reloj quieto.
    ///
    /// **Parado significa quieto**, no «sigue contando pero nadie mira». Si el
    /// tiempo siguiera corriendo, el playhead se movería sin que sonara nada, y
    /// una animación no derivada del reloj musical es un antipatrón declarado en
    /// `product-guidelines.md`.
    ///
    /// Realtime: llamado desde el hilo del scheduler al salir del bucle.
    /// Sin asignaciones, sin locks, sin await.
    func stop() {
        origin.value = 0
    }

    /// Tiempo que lleva sonando el transporte, o `nil` si está parado.
    ///
    /// `nil` no es un error: es el estado de reposo, y es lo que hace que el
    /// playhead se quede donde está en vez de inventarse una posición.
    ///
    /// Un `now` anterior al origen se lee como cero. No puede ocurrir con un
    /// reloj monótono, pero devolver una resta envolvente —un número enorme—
    /// mandaría el playhead a una posición arbitraria del anillo.
    ///
    /// Lo llama la interfaz al redibujar. No es código de tiempo real.
    public func elapsedNanoseconds(now: UInt64 = HostClock.now()) -> Int64? {
        let start = origin.value
        guard start != 0 else { return nil }
        guard now > start else { return 0 }

        return Int64(HostClock.nanoseconds(fromHostTicks: now &- start))
    }
}
