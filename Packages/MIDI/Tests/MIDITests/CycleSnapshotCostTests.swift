import Engine
import XCTest

@testable import MIDI

/// Ver la nota de `PatternHandoffTests` sobre la ambigüedad del nombre en los
/// targets de test.
private typealias Pattern = Engine.Pattern

/// Cuánto costaría el snapshot cuando el Track contenga dieciséis Cycles.
///
/// **Esta es la incógnita por la que la Fase 1 va primero.** La rebanada decide
/// avanzar el Cycle en el hilo del scheduler, y eso obliga a que los 256 Cycles
/// —dieciséis Tracks por dieciséis Cycles— viajen en el snapshot que ese hilo
/// copia una vez por ventana. Si esa copia no cabe holgadamente en la ventana de
/// 20 ms, el diseño entero cambia: el avance se iría al hilo principal o habría
/// que publicar por Track. Más vale saberlo antes de renombrar medio motor.
///
/// **Se mide sobre un tipo de prueba, no sobre el modelo.** Aquí no se renombra
/// nada: `ProbePattern` tiene la forma que tendrá el modelo después de la Fase 2
/// —el `Track` de hoy es el `Cycle` de mañana— y sirve para poner un número
/// delante de la decisión sin haber tocado `Engine`.
///
/// El coste se mide en `debug`, que es donde corren los tests y donde se midió
/// la referencia del 2026-08-31 (2,25 KB en 274 ns). En release es más barato:
/// la comparación honesta es contra aquella cifra, no contra el reloj de la app.
final class CycleSnapshotCostTests: XCTestCase {

    // MARK: - La forma que tendrá el modelo

    /// El `Cycle` de la Pre Spec es el `Track` de hoy: Shape, pool, marco tonal,
    /// Groove y canal. No se declara un tipo nuevo para no inventar una segunda
    /// definición de lo mismo antes de que la Fase 2 haga el renombrado.
    private typealias ProbeCycle = Track

    /// El `Track` que viene: dieciséis Cycles, cuántos están activos y por cuál
    /// va.
    ///
    /// La tupla es deliberada, por la misma razón que en `Pattern`: un `Array`
    /// metería conteo de referencias en un valor que se copia dentro del hilo
    /// del scheduler. Los dos contadores son `Int32` porque 1–16 cabe de sobra y
    /// porque así el tipo no gana relleno.
    private struct ProbeTrack {
        var cycles:
            (
                ProbeCycle, ProbeCycle, ProbeCycle, ProbeCycle,
                ProbeCycle, ProbeCycle, ProbeCycle, ProbeCycle,
                ProbeCycle, ProbeCycle, ProbeCycle, ProbeCycle,
                ProbeCycle, ProbeCycle, ProbeCycle, ProbeCycle
            )
        var activeCount: Int32
        var cursor: Int32
    }

    /// Los dieciséis Tracks, cada uno con sus dieciséis Cycles: 256 en total.
    private struct ProbePattern {
        var tracks:
            (
                ProbeTrack, ProbeTrack, ProbeTrack, ProbeTrack,
                ProbeTrack, ProbeTrack, ProbeTrack, ProbeTrack,
                ProbeTrack, ProbeTrack, ProbeTrack, ProbeTrack,
                ProbeTrack, ProbeTrack, ProbeTrack, ProbeTrack
            )
    }

    /// El handoff, con la misma disciplina de ranura y sobre cualquier valor.
    ///
    /// **Es una copia del protocolo de `PatternHandoff`, no una simplificación**:
    /// mismas cuatro ranuras reservadas al construir, mismo contador de
    /// generación atómico, misma lectura que copia la ranura y vuelve a mirar el
    /// contador. Si midiera otra cosa, el número no valdría para decidir.
    ///
    /// Vive en los tests porque generalizar `PatternHandoff` para medir sería
    /// cambiar producción por una pregunta que se responde una vez.
    private final class ProbeHandoff<Value>: @unchecked Sendable {
        private static var slotCount: Int { 4 }
        private let slots: UnsafeMutablePointer<Value>
        private let generation = AtomicCounter(0)

        init(_ initial: Value) {
            slots = .allocate(capacity: Self.slotCount)
            slots.initialize(repeating: initial, count: Self.slotCount)
        }

        deinit {
            slots.deinitialize(count: Self.slotCount)
            slots.deallocate()
        }

        func load() -> Value? {
            let before = generation.value
            let value = slots[Int(before & UInt64(Self.slotCount - 1))]
            let after = generation.value
            guard after &- before < UInt64(Self.slotCount - 1) else { return nil }
            return value
        }
    }

    // MARK: - Los tamaños

    /// El snapshot de Cycles son los 256 Cycles y dos contadores por Track, y
    /// nada más: si algún día crece por otro sitio, esto lo dice.
    func testTheCycleSnapshotIsTwoHundredFiftySixCyclesWide() {
        XCTAssertEqual(
            MemoryLayout<ProbeTrack>.size,
            MemoryLayout<ProbeCycle>.size * 16 + MemoryLayout<Int32>.size * 2)
        XCTAssertEqual(MemoryLayout<ProbePattern>.size, MemoryLayout<ProbeTrack>.size * 16)
    }

    /// Sigue siendo trivial con el nivel nuevo dentro: copiarlo en el hilo del
    /// scheduler no puede tocar el conteo de referencias.
    ///
    /// Es la restricción que la Fase 2 tiene que preservar, y la razón por la
    /// que el almacenamiento es inline y de tamaño fijo.
    func testTheCycleSnapshotIsStillATrivialType() {
        XCTAssertTrue(_isPOD(ProbeTrack.self), "el Track con Cycles dejó de ser trivial")
        XCTAssertTrue(_isPOD(ProbePattern.self), "el Pattern con Cycles dejó de ser trivial")
    }

    // MARK: - El coste

    /// Un `load()` del snapshot con los 256 Cycles, contra la ventana de 20 ms.
    ///
    /// **El presupuesto es el 1% de la ventana**, es decir 200 µs. Por encima se
    /// para y se decide otro diseño, que es lo que la tarea siguiente hace con
    /// este número delante.
    ///
    /// La cota que se afirma es la del presupuesto, no la del número medido: un
    /// test que fijara los nanosegundos exactos fallaría en cualquier máquina
    /// distinta y no diría nada de la decisión. El número medido se registra en
    /// la git note y en la documentación de `PatternHandoff`.
    func testOneLoadOfTheCycleSnapshotFitsWellInsideTheWindow() {
        let nanosecondsPerLoad = measureLoad(of: probePattern())
        let windowNanoseconds = 20_000_000.0

        print(
            "Cycles: MemoryLayout<ProbePattern> = \(MemoryLayout<ProbePattern>.size) bytes, "
                + "load() = \(String(format: "%.0f", nanosecondsPerLoad)) ns, "
                + "\(String(format: "%.4f", nanosecondsPerLoad / windowNanoseconds * 100))% "
                + "de la ventana")

        XCTAssertLessThan(
            nanosecondsPerLoad, windowNanoseconds / 100,
            "un load() del snapshot con Cycles se come más del 1% de la ventana")
    }

    /// El mismo banco sobre el snapshot de hoy, que es lo que hace comparable el
    /// número de arriba.
    ///
    /// Sin esta medición, comparar contra los 274 ns del 2026-08-31 sería
    /// comparar contra otra máquina y otro compilador. Con ella, lo que se
    /// compara es la **razón** entre los dos tamaños en la misma pasada.
    func testTodaysSnapshotIsMeasuredInTheSameRunSoTheComparisonIsFair() {
        let nanosecondsPerLoad = measureLoad(of: Pattern.initial)

        print(
            "Hoy: MemoryLayout<Pattern> = \(MemoryLayout<Pattern>.size) bytes, "
                + "load() = \(String(format: "%.0f", nanosecondsPerLoad)) ns")

        XCTAssertLessThan(nanosecondsPerLoad, 20_000_000.0 / 100)
    }

    /// El anillo entero, que es lo que se reserva al construir el handoff.
    ///
    /// **No es coste por ventana sino memoria residente**, y por eso se mira
    /// aparte: cuatro ranuras de un snapshot de Cycles son unos 147 KB que viven
    /// mientras viva el transporte. Es la cifra que hay que tener delante si
    /// algún día se plantea subir el número de ranuras.
    func testTheRingIsFourSlotsAndStaysReasonable() {
        let ringBytes = MemoryLayout<ProbePattern>.size * 4
        print("Cycles: anillo de 4 ranuras = \(ringBytes) bytes")

        XCTAssertLessThan(ringBytes, 1_048_576, "el anillo dejó de ser memoria despreciable")
    }

    // MARK: - Material de prueba

    /// Un Pattern de prueba con los 256 Cycles poblados.
    ///
    /// Se rellena con material real —no con ceros— porque copiar es copiar
    /// bytes: lo que se mide es el tamaño, y poblarlo evita medir sobre una
    /// página que el sistema no ha tocado.
    private func probePattern() -> ProbePattern {
        let cycle = ProbeCycle(
            shape: Shape(steps: Steps(16)!, pulses: Pulses(5)!),
            pool: PitchPool().inserting(Pitch(48)!)
        )
        let track = ProbeTrack(
            cycles: (
                cycle, cycle, cycle, cycle, cycle, cycle, cycle, cycle,
                cycle, cycle, cycle, cycle, cycle, cycle, cycle, cycle
            ),
            activeCount: 16,
            cursor: 0
        )
        return ProbePattern(
            tracks: (
                track, track, track, track, track, track, track, track,
                track, track, track, track, track, track, track, track
            ))
    }

    // MARK: - Banco

    /// Nanosegundos por `load()`, promediados sobre muchas lecturas.
    ///
    /// El acumulador existe para que el optimizador no pueda descartar la copia:
    /// sin él, medir una lectura cuyo resultado nadie mira no mediría nada.
    private func measureLoad<Value>(of value: Value, iterations: Int = 200_000) -> Double {
        let handoff = ProbeHandoff(value)
        var sink: UInt64 = 0

        // Una pasada corta antes de medir: la primera lectura de cada ranura
        // paga fallos de caché que no son el coste en régimen.
        for _ in 0..<10_000 where handoff.load() != nil { sink &+= 1 }

        let started = HostClock.now()
        for _ in 0..<iterations where handoff.load() != nil { sink &+= 1 }
        let elapsed = HostClock.nanoseconds(fromHostTicks: HostClock.now() &- started)

        XCTAssertGreaterThan(sink, 0, "el banco no llegó a leer nada")
        return Double(elapsed) / Double(iterations)
    }
}
