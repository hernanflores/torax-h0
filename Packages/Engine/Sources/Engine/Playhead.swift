/// Dónde está el tiempo sobre el anillo.
///
/// **El movimiento deriva del reloj.** `product-guidelines.md` lo pide como
/// regla y lo repite como antipatrón: ninguna animación que no comunique tiempo
/// musical. Este tipo es esa derivación, y no tiene estado propio — dado el
/// tiempo transcurrido desde que arrancó el transporte, dice qué Step suena y
/// en qué punto de la vuelta va.
///
/// **Por qué el ancla es el tiempo y no el último Step entregado.** El
/// scheduler trabaja por adelantado: entrega los Steps hasta una ventana de
/// look-ahead **antes** de que suenen. Mostrar el último Step entregado pondría
/// el playhead por delante de lo que se oye, que es justo el desfase que la
/// pantalla existe para no tener. Contra el tiempo transcurrido, en cambio, la
/// posición es la que suena por construcción.
///
/// **Por qué la fracción es continua.** El Step dice qué está sonando; la
/// fracción de vuelta permite dibujar el playhead *entre* dos posiciones. Sin
/// ella el playhead saltaría de marca en marca, que a Divisions lentas se ve
/// como un reloj roto en vez de como tiempo que transcurre.
///
/// No es código de tiempo real: lo consulta la interfaz al redibujar.
public struct Playhead: Equatable, Sendable {

    /// Step que está sonando, ya envuelto sobre el anillo.
    public let step: Int

    /// Punto de la vuelta, como fracción en `[0, 1)`.
    ///
    /// Misma unidad que `Ring.Position.turn`, y a propósito: la vista dibuja
    /// las dos cosas con la misma conversión a ángulo.
    public let turn: Double

    /// Sitúa el playhead a partir del tiempo que lleva sonando el transporte.
    ///
    /// Un tiempo negativo se trata como el origen. No puede ocurrir con el
    /// transporte corriendo, pero inventar una posición fuera del anillo sería
    /// peor que quedarse en el principio.
    public init(elapsedNanoseconds: Int64, timeline: MusicalTimeline, steps: Steps) {
        guard elapsedNanoseconds > 0 else {
            step = 0
            turn = 0
            return
        }

        let stepDuration = timeline.stepDurationNanoseconds
        let ringDuration = stepDuration * Double(steps.count)

        // **Se mide desde el origen virtual de la rejilla, no desde Play**
        // (FR9 de `division-hot-grid_20260911`). Una rejilla reanclada cuenta
        // sus Steps desde el ancla, así que el Step 0 «virtual» cae donde la
        // Division nueva lo pondría. Sin ancla ese origen es Play y la suma de
        // abajo es `Double(elapsed) + 0`, el mismo número de siempre (FR11).
        let sinceOrigin =
            Double(elapsedNanoseconds - timeline.anchorNanoseconds)
            + stepDuration * Double(timeline.anchorStep)
        var intoRing = sinceOrigin.truncatingRemainder(dividingBy: ringDuration)
        // Antes del ancla la cuenta puede ser negativa; se envuelve al anillo,
        // y el borde exacto se queda en el principio de la vuelta y no en 1.
        if intoRing < 0 { intoRing += ringDuration }
        if intoRing >= ringDuration { intoRing = 0 }

        turn = intoRing / ringDuration
        // El Step sale de la fracción y no de una segunda división, para que los
        // dos no puedan discrepar por redondeo en el borde de un Step.
        step = min(Int(turn * Double(steps.count)), steps.count - 1)
    }
}

extension Playhead {

    /// Dónde está el tiempo en **cada uno** de los dieciséis Tracks.
    ///
    /// **Los dieciséis anillos no van en fase, y por eso hacen falta dieciséis
    /// playheads.** Cada Track tiene su Division y sus Steps, así que su vuelta
    /// dura otra cosa: a la misma marca de tiempo, dos Tracks pueden estar en
    /// puntos muy distintos de sus respectivas vueltas. Un solo playhead sería
    /// correcto para uno y mentiría sobre los otros quince.
    ///
    /// **Los dieciséis siempre, tengan material o no.** El anillo de un Track
    /// vacío se dibuja igual —si apareciera y desapareciera, los demás se
    /// moverían de sitio— y su rejilla avanza igual: lo único que no hace es
    /// emitir.
    ///
    /// **La rejilla de cada Track es la que publica el scheduler**, en `grids`:
    /// la misma con la que programa, anclada donde reancló. Es lo que garantiza
    /// que lo que se ve y lo que suena no puedan discrepar, también después de
    /// girar Division (FR9 de `division-hot-grid_20260911`). Antes de ese track
    /// bastaba con reconstruirla desde la Division del Track, porque no
    /// cambiaba nunca.
    ///
    /// Sin rejilla publicada para un Track —el arnés, o `grids` en `nil`— se
    /// reconstruye como antes: `MusicalTimeline(tempo:division:)` con la
    /// Division del Cycle en edición.
    ///
    /// No es código de tiempo real: lo consulta la interfaz al redibujar.
    public static func forEachTrack(
        in pattern: Pattern,
        tempo: Tempo,
        elapsedNanoseconds: Int64,
        grids: [PlaybackGrid?]? = nil
    ) -> [Playhead] {
        (0..<Pattern.trackCount).map { index in
            // Sobre el Cycle en edición, que es el que se dibuja: el playhead
            // tiene que caer sobre el anillo que se está viendo, o marcaría una
            // posición de un anillo que no está en pantalla.
            let cycle = pattern.editingCycle(at: index) ?? Pattern.emptyCycle
            // Los Steps son los del anillo que se ve; el tiempo, el de la
            // rejilla que suena.
            let published = grids.flatMap { index < $0.count ? $0[index] : nil }
            return Playhead(
                elapsedNanoseconds: elapsedNanoseconds,
                timeline: published?.timeline(atNanoseconds: elapsedNanoseconds)
                    ?? MusicalTimeline(tempo: tempo, division: cycle.shape.division),
                steps: cycle.shape.steps
            )
        }
    }
}
