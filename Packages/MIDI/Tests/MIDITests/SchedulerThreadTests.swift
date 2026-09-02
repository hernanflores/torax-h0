import CToraxAtomics
import Engine
import XCTest
@testable import MIDI

final class AtomicFlagTests: XCTestCase {

    /// La razón de ser del target C es evitar locks en el hilo del scheduler.
    /// Si la plataforma emulara `_Atomic` con un lock interno, todo el diseño
    /// se vendría abajo en silencio.
    func testAtomicsAreActuallyLockFree() {
        XCTAssertTrue(
            tx_atomics_is_lock_free(),
            "Los atomicos se estan emulando con lock: el hilo del scheduler podria bloquearse")
    }

    func testFlagStartsWithGivenValue() {
        XCTAssertFalse(AtomicFlag(false).value)
        XCTAssertTrue(AtomicFlag(true).value)
    }

    func testFlagRoundTrips() {
        let flag = AtomicFlag(false)
        flag.value = true
        XCTAssertTrue(flag.value)
        flag.value = false
        XCTAssertFalse(flag.value)
    }

    /// Escrituras desde varios hilos no deben corromper el valor: siempre es
    /// `true` o `false`, nunca basura.
    func testFlagSurvivesConcurrentAccess() {
        let flag = AtomicFlag(false)
        let expectation = expectation(description: "hilos terminan")
        expectation.expectedFulfillmentCount = 8

        for index in 0..<8 {
            Thread.detachNewThread {
                for _ in 0..<10_000 {
                    flag.value = index.isMultiple(of: 2)
                    _ = flag.value
                }
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 10)
    }
}

final class AtomicCounterTests: XCTestCase {

    func testCounterStartsAtZero() {
        XCTAssertEqual(AtomicCounter().value, 0)
    }

    /// El conteo desde varios hilos no puede perder incrementos: es lo que
    /// garantiza que el arnés de jitter no reporte menos eventos de los
    /// realmente emitidos.
    func testConcurrentIncrementsAreNotLost() {
        let counter = AtomicCounter()
        let expectation = expectation(description: "hilos terminan")
        expectation.expectedFulfillmentCount = 8

        for _ in 0..<8 {
            Thread.detachNewThread {
                for _ in 0..<10_000 { counter.increment() }
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 10)
        XCTAssertEqual(counter.value, 80_000)
    }
}

final class SchedulerThreadTests: XCTestCase {

    private func makeConfiguration() -> SchedulerConfiguration {
        SchedulerConfiguration(
            timeline: MusicalTimeline(tempo: Tempo(beatsPerMinute: 120)!, division: .sixteenth),
            lookAheadNanoseconds: 20_000_000
        )
    }

    func testThreadIsNotRunningBeforeStart() {
        let thread = SchedulerThread(configuration: makeConfiguration()) { _, _, _, _, _, _ in }
        XCTAssertFalse(thread.isRunning)
    }

    func testStartThenStopLeavesThreadStopped() {
        let thread = SchedulerThread(configuration: makeConfiguration()) { _, _, _, _, _, _ in }
        thread.start()
        XCTAssertTrue(thread.isRunning)
        thread.stop()
        XCTAssertFalse(thread.isRunning)
    }

    /// El hilo debe emitir Steps en orden y sin repetirlos: es el invariante del
    /// scheduler visto desde fuera.
    func testThreadEmitsStepsInOrder() {
        let emitted = AtomicCounter()
        let outOfOrder = AtomicFlag(false)
        let lastStep = AtomicCounter()

        let thread = SchedulerThread(configuration: makeConfiguration()) { _, _, step, _, _, _ in
            if step > 0 && UInt64(step) != lastStep.value + 1 { outOfOrder.value = true }
            lastStep.value = UInt64(step)
            emitted.increment()
        }

        thread.start()
        let deadline = Date().addingTimeInterval(2)
        while emitted.value < 8 && Date() < deadline { usleep(5_000) }
        thread.stop()

        XCTAssertGreaterThanOrEqual(emitted.value, 8, "El hilo deberia haber emitido Steps")
        XCTAssertFalse(outOfOrder.value, "Los Steps se emitieron fuera de orden")
    }

    func testStoppingTwiceIsHarmless() {
        let thread = SchedulerThread(configuration: makeConfiguration()) { _, _, _, _, _, _ in }
        thread.start()
        thread.stop()
        thread.stop()
        XCTAssertFalse(thread.isRunning)
    }
}
