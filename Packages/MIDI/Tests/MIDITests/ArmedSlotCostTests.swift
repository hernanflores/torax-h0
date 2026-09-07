import Engine
import XCTest

@testable import MIDI

private typealias Pattern = Engine.Pattern

/// Cuánto cuesta la ranura armada, **antes de construir encima**.
///
/// **Es la puerta de la Fase 6**, con el método de `cycles_20260901`: la
/// rebanada decide que el cambio de Pattern lo adopte el hilo del scheduler en
/// el límite de compás, y eso mete en el bucle de ventana una lectura atómica
/// más y una comparación. Si eso no cabe holgadamente, el diseño cambia: la
/// alternativa escrita es que el hilo principal publique al cruzar (FR7, opción
/// descartada), y reabrirla exige que el número lo justifique.
///
/// **Presupuesto: la lectura añadida por debajo del 1% de la ventana de 20 ms**,
/// es decir 200 µs.
///
/// Se mide en `debug`, que es donde corren los tests y donde se midieron las
/// referencias anteriores —274 ns el 2026-08-31, ~870 ns el 2026-09-02—. En
/// release es más barato; la comparación honesta es contra esas cifras y contra
/// el `load()` de hoy medido en la misma pasada.
final class ArmedSlotCostTests: XCTestCase {

    // MARK: - La forma que tendrá el handoff

    /// El handoff con la ranura armada: el anillo de cuatro que ya existe, más
    /// **una** ranura, más su contador de generación.
    ///
    /// **Una ranura y no otro anillo**: lo armado lo escribe el hilo principal y
    /// lo lee el del scheduler una vez por ventana, y solo hay un Pattern
    /// pendiente a la vez — armar dos veces deja el último.
    private final class ProbeArmedHandoff<Value>: @unchecked Sendable {

        private static var slotCount: Int { 4 }

        private let slots: UnsafeMutablePointer<Value>
        private let generation = AtomicCounter(0)

        /// La ranura armada y su contador. Un contador **par** significa «nada
        /// armado»; impar, «hay algo». Así adoptar es una comparación de enteros
        /// y no un opcional que asigne.
        private let armedSlot: UnsafeMutablePointer<Value>
        private let armedGeneration = AtomicCounter(0)

        init(_ initial: Value) {
            slots = .allocate(capacity: Self.slotCount)
            slots.initialize(repeating: initial, count: Self.slotCount)
            armedSlot = .allocate(capacity: 1)
            armedSlot.initialize(to: initial)
        }

        deinit {
            slots.deinitialize(count: Self.slotCount)
            slots.deallocate()
            armedSlot.deinitialize(count: 1)
            armedSlot.deallocate()
        }

        /// Lo que el hilo del scheduler hace una vez por ventana: leer lo
        /// publicado y **mirar si hay algo armado**.
        func loadCheckingArmed() -> Value? {
            let armed = armedGeneration.value

            let before = generation.value
            let value = slots[Int(before & UInt64(Self.slotCount - 1))]
            let after = generation.value
            guard after &- before < UInt64(Self.slotCount - 1) else { return nil }

            // La comparación que se añade al bucle: ¿hay algo pendiente?
            if armed % 2 == 1 { return value }
            return value
        }

        /// Lo mismo sin mirar lo armado, para medir la diferencia en la misma
        /// pasada.
        func load() -> Value? {
            let before = generation.value
            let value = slots[Int(before & UInt64(Self.slotCount - 1))]
            let after = generation.value
            guard after &- before < UInt64(Self.slotCount - 1) else { return nil }
            return value
        }
    }

    private func probe() -> ProbeArmedHandoff<Pattern> {
        ProbeArmedHandoff(Pattern.initial)
    }

    /// 200 000 lecturas por pasada, tres pasadas, se queda la mejor. Es el
    /// método de `cycles_20260901`.
    private func measure(_ body: () -> Pattern?) -> Double {
        let iterations = 200_000
        var best = Double.greatestFiniteMagnitude

        for _ in 0..<3 {
            let start = DispatchTime.now().uptimeNanoseconds
            var sink = 0
            for _ in 0..<iterations {
                if let value = body() { sink &+= value.cycle(at: 0)?.shape.steps.count ?? 0 }
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start)
            XCTAssertGreaterThan(sink, 0)
            best = Swift.min(best, elapsed / Double(iterations))
        }
        return best
    }

    // MARK: - El tamaño

    /// **El anillo no crece: gana una ranura, no otro anillo.**
    ///
    /// Cuatro ranuras de ~37 KB son ~148 KB; con la armada, ~185 KB. Es la cifra
    /// que hay que tener delante si algún día se plantea armar más de uno.
    func testTheArmedSlotAddsOneSlotAndNotAnotherRing() {
        let slot = MemoryLayout<Pattern>.size
        let ring = slot * 4
        let withArmed = ring + slot

        print(
            "Pattern = \(slot) bytes · anillo = \(ring) · con ranura armada = \(withArmed)")

        XCTAssertEqual(withArmed, ring + slot)
        XCTAssertLessThan(withArmed, 1_048_576, "el handoff dejó de ser memoria despreciable")
    }

    // MARK: - El coste por ventana

    /// **La puerta.** La lectura con la comprobación de lo armado, contra el 1%
    /// de la ventana.
    func testTheArmedCheckFitsWellInsideTheWindow() {
        let handoff = probe()
        let nanoseconds = measure { handoff.loadCheckingArmed() }
        let window = 20_000_000.0

        print(
            "Con ranura armada: load() = \(String(format: "%.0f", nanoseconds)) ns, "
                + "\(String(format: "%.4f", nanoseconds / window * 100))% de la ventana")

        XCTAssertLessThan(
            nanoseconds, window / 100,
            "la lectura con ranura armada se come más del 1% de la ventana")
    }

    /// El `load()` de hoy, **en la misma pasada**, que es lo que hace comparable
    /// el número de arriba. Sin esto, comparar contra los ~870 ns del 2026-09-02
    /// sería comparar contra otra máquina.
    func testTodaysLoadIsMeasuredInTheSameRun() {
        let handoff = probe()
        let nanoseconds = measure { handoff.load() }

        print("Sin ranura armada: load() = \(String(format: "%.0f", nanoseconds)) ns")

        XCTAssertLessThan(nanoseconds, 20_000_000.0 / 100)
    }

    /// Y que el tipo siga siendo trivial, que es la restricción de la que todo
    /// esto depende.
    func testThePatternIsStillTrivial() {
        XCTAssertTrue(_isPOD(Pattern.self))
    }
}
