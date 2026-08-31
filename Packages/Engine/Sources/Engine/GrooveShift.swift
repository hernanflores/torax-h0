/// El desplazamiento temporal que Groove aplica a la rejilla.
///
/// **Es donde vive la corrección de la rebanada 6.** `MusicalTimeline` dice
/// dónde cae cada Step; esto dice cuánto se aparta de ahí. La suma de los dos es
/// el instante de emisión, y separarlos deja la rejilla intacta y testeable por
/// su cuenta.
///
/// **Aritmética entera, en nanosegundos, sin coma flotante.** Esto corre en el
/// hilo del scheduler. El orden de las operaciones —multiplicar antes de
/// dividir— conserva la precisión que dividir primero perdería, igual que en
/// `Sustain.gateNanoseconds(forStep:)`.
extension Groove {

    /// Cuánto se aparta de la rejilla el Step indicado.
    ///
    /// Positivo atrasa, negativo adelanta. Es la suma de los dos parámetros
    /// temporales: `Timing` mueve solo los Steps impares, `Delay` los mueve
    /// todos.
    ///
    /// **La paridad es la del índice absoluto de la rejilla, no la de la
    /// posición en el anillo.** El swing es una propiedad del tiempo musical y
    /// no del patrón: con un número impar de Steps, el anillo y la rejilla del
    /// swing desfasan de una vuelta a la siguiente, que es lo que hace una caja
    /// de ritmos. Ligarlo al anillo produciría un swing que cambia de sentido al
    /// girar el knob de Steps.
    ///
    /// Los índices negativos siguen la misma paridad —en Swift el resto conserva
    /// el signo, así que `-1 % 2` no es cero y el Step −1 es impar—.
    /// `MusicalTimeline` los admite desde la rebanada 1 y `Delay` es quien los
    /// produce.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    /// Calculates how far a step departs from the grid.
    /// - Parameters:
    ///   - step: The absolute step index on the timeline.
    ///   - stepDurationNanoseconds: The step duration in nanoseconds.
    /// - Returns: The shift in nanoseconds; positive delays the step, negative advances it.
    public func shiftNanoseconds(atStep step: Int, stepDurationNanoseconds: Int64) -> Int64 {
        swingNanoseconds(atStep: step, stepDurationNanoseconds: stepDurationNanoseconds)
            + delayNanoseconds(forStep: stepDurationNanoseconds)
    }

    /// Cuánto tiempo hay que reservar por delante para que ningún evento se pida
    /// para un instante que ya pasó.
    ///
    /// **La misma cantidad resuelve los dos sitios donde el problema aparece:**
    /// el origen de la rejilla, que pasa a ser `Play + presupuesto`, y el
    /// horizonte de selección, que se amplía en él mientras suena. Enmienda
    /// fechada del 2026-08-30 en `tech-stack.md`.
    ///
    /// **Con Delay ≥ 0 vale exactamente cero**, y eso es lo que importa: la
    /// mitad positiva del rango —donde vive el default— no paga ni latencia de
    /// arranque, ni horizonte más largo, ni respuesta de knob más lenta. Fijarlo
    /// al máximo del rango habría sido más simple y habría alargado el
    /// look-ahead un Step entero para todo el mundo, rompiendo «un giro debe
    /// oírse en el step siguiente» para quien no usa el parámetro.
    ///
    /// `Timing` no entra aquí: solo atrasa.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    /// Calculates the time to reserve ahead so that no advanced event lands in the past.
    /// - Parameter stepDurationNanoseconds: The step duration in nanoseconds.
    /// - Returns: The advance budget in nanoseconds; zero when nothing is advanced.
    public func advanceBudgetNanoseconds(forStep stepDurationNanoseconds: Int64) -> Int64 {
        max(0, -delayNanoseconds(forStep: stepDurationNanoseconds))
    }

    /// El desplazamiento de `Timing`, que solo alcanza a los Steps impares.
    ///
    /// El porcentaje es la **posición del segundo Step del par dentro del par**,
    /// así que lo que se desplaza es lo que ese porcentaje se aparta de la mitad,
    /// medido sobre la duración del par —dos Steps—:
    ///
    ///     desplazamiento = (percent − 50) / 100 · 2 · duración de Step
    ///
    /// Al 50% es cero sin necesidad de interceptar el caso; al 75%, medio Step.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private func swingNanoseconds(atStep step: Int, stepDurationNanoseconds: Int64) -> Int64 {
        guard step % 2 != 0 else { return 0 }
        return stepDurationNanoseconds * Int64(2 * (timing.percent - Timing.straight.percent)) / 100
    }

    /// El desplazamiento de `Delay`, que alcanza a todos los Steps por igual.
    ///
    /// Realtime: llamado desde el hilo del scheduler.
    /// Sin asignaciones, sin locks, sin await.
    private func delayNanoseconds(forStep stepDurationNanoseconds: Int64) -> Int64 {
        stepDurationNanoseconds * Int64(delay.percent) / 100
    }
}
