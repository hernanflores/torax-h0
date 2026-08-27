import Darwin
import Engine
import Foundation
import XCTest
@testable import MIDI

/// Tests de la carrera entre `stop()` y `start()`.
///
/// **El defecto.** `stop()` solo baja una bandera atómica; el hilo está dormido
/// y tarda hasta media ventana en verla. Si `start()` llega antes, vuelve a
/// subirla y el hilo viejo nunca llega a leer el `false`: quedan dos bucles
/// vivos, cada uno con su origen temporal y su `LookAheadScheduler`, emitiendo
/// cada Step dos veces.
///
/// **Cómo se detecta, y por qué así.** No por Steps repetidos: cada `start()`
/// reinicia la cuenta en cero, así que ver el Step 0 otra vez es esperado. Y
/// tampoco basta con mirar si el hilo viejo emite algo justo después de
/// `stop()`, que también es esperado mientras `stop()` no espere.
///
/// Lo que no admite otra lectura es **el ritmo de emisión**: dos bucles emiten
/// al doble de velocidad que uno. Se mide la tasa en régimen estable, después
/// de los ciclos rápidos, y se compara con la que dicta la línea de tiempo.
final class SchedulerLifecycleTests: XCTestCase {

    /// 300 BPM con Division 1/256 da Steps de 3,125 ms contra una ventana de
    /// 20 ms.
    ///
    /// La proporción es deliberada: con los 125 ms por Step del resto de los
    /// tests, un bucle huérfano no llega a emitir nada dentro de la ventana y el
    /// test pasaría aunque la carrera existiera.
    private static let stepNanoseconds = 3_125_000.0

    private func configuration() -> SchedulerConfiguration {
        SchedulerConfiguration(
            timeline: MusicalTimeline(
                tempo: Tempo(beatsPerMinute: 300)!,
                division: Division(numerator: 1, denominator: 256)!
            ),
            lookAheadNanoseconds: 20_000_000
        )
    }

    /// Emisiones por segundo que produce **un** scheduler con esa línea de
    /// tiempo: unas 320.
    private static var expectedRatePerSecond: Double { 1_000_000_000.0 / stepNanoseconds }

    // MARK: - La carrera

    /// Ciclos rápidos de `stop()`/`start()` no pueden dejar más de un bucle vivo.
    ///
    /// Sin la guarda, cada ciclo deja un bucle huérfano y la tasa se multiplica
    /// por el número de ciclos.
    func testRapidStopStartLeavesExactlyOneSchedulerRunning() {
        let emitted = AtomicCounter()
        let thread = SchedulerThread(configuration: configuration()) { _, _ in
            emitted.increment()
        }
        defer { thread.stop() }

        thread.start()
        usleep(30_000)

        // Los ciclos van sin pausa entre medias: es lo que mete el `start()`
        // dentro de la ventana en la que el hilo viejo sigue dormido.
        for _ in 0..<5 {
            thread.stop()
            thread.start()
        }

        // Régimen estable: se deja pasar la ventana para que cualquier bucle
        // huérfano ya esté emitiendo, y solo entonces se mide.
        usleep(60_000)

        let before = emitted.value
        let measuredSeconds = 0.4
        usleep(UInt32(measuredSeconds * 1_000_000))
        let observedRate = Double(emitted.value - before) / measuredSeconds

        // Margen generoso hacia arriba: un solo bucle puede adelantarse un poco
        // por el borde de la ventana, pero no puede acercarse al doble.
        XCTAssertLessThan(
            observedRate,
            Self.expectedRatePerSecond * 1.5,
            """
            Se emitieron \(Int(observedRate)) Steps/s cuando un solo scheduler \
            emite \(Int(Self.expectedRatePerSecond)). Hay más de un bucle vivo: \
            `start()` volvió a subir la bandera antes de que el hilo viejo la \
            leyera.
            """
        )
        XCTAssertGreaterThan(observedRate, 0, "no quedó ningún scheduler vivo")
    }

    // MARK: - `stop()` significa parar

    /// Cuando `stop()` retorna, el handler no vuelve a invocarse. Ni un Step más.
    func testNoStepIsEmittedAfterStopReturns() {
        let emitted = AtomicCounter()
        let thread = SchedulerThread(configuration: configuration()) { _, _ in
            emitted.increment()
        }

        thread.start()
        usleep(40_000)
        thread.stop()

        let atStop = emitted.value
        usleep(200_000)

        XCTAssertEqual(
            emitted.value,
            atStop,
            "el hilo emitió \(emitted.value - atStop) Steps después de que `stop()` retornara"
        )
    }

    // MARK: - Parar informa, y nunca cuelga

    func testStoppingAFreshSchedulerReportsStopped() {
        let thread = SchedulerThread(configuration: configuration()) { _, _ in }
        XCTAssertEqual(thread.stop(), .stopped, "parar sin haber arrancado debería ser inmediato")
    }

    func testStoppingARunningSchedulerReportsStopped() {
        let thread = SchedulerThread(configuration: configuration()) { _, _ in }
        thread.start()
        usleep(30_000)
        XCTAssertEqual(thread.stop(), .stopped)
    }

    /// La espera tiene cota, pero el caso normal ni se acerca a ella: el bucle
    /// duerme media ventana, así que sale en ese orden de magnitud.
    func testStoppingReturnsWellWithinItsBound() {
        let thread = SchedulerThread(configuration: configuration()) { _, _ in }
        thread.start()
        usleep(30_000)

        let before = HostClock.now()
        XCTAssertEqual(thread.stop(), .stopped)
        let elapsed = HostClock.nanoseconds(fromHostTicks: HostClock.now() &- before)

        XCTAssertLessThan(
            elapsed,
            100_000_000,
            "parar tardó \(elapsed / 1_000_000) ms; la ventana es de 20 ms"
        )
    }

    // MARK: - Reiniciar no solapa bucles

    /// Tras parar y arrancar, los Steps vuelven a empezar en cero y avanzan de
    /// uno en uno: es el invariante que `LookAheadScheduler` promete.
    func testRestartEmitsOneContiguousSequence() {
        let outOfOrder = AtomicFlag(false)
        let lastStep = AtomicCounter()
        let emitted = AtomicCounter()

        let thread = SchedulerThread(configuration: configuration()) { step, _ in
            if step != 0 && UInt64(step) != lastStep.value &+ 1 { outOfOrder.value = true }
            lastStep.value = UInt64(step)
            emitted.increment()
        }
        defer { thread.stop() }

        thread.start()
        usleep(40_000)
        thread.stop()

        lastStep.value = 0
        outOfOrder.value = false
        thread.start()
        usleep(80_000)

        XCTAssertGreaterThan(emitted.value, 0, "no emitió nada tras reiniciar")
        XCTAssertFalse(
            outOfOrder.value,
            "los Steps no fueron contiguos tras reiniciar: hay dos bucles emitiendo"
        )
    }
}
