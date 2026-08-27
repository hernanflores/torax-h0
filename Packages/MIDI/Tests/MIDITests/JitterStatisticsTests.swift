import XCTest
@testable import MIDI

/// Tests de la estadística de jitter sobre series conocidas.
///
/// Es la pieza que convierte el criterio de éxito del track en un número, así
/// que su aritmética tiene que ser indiscutible: un error aquí haría aprobar o
/// suspender la arquitectura por el motivo equivocado.
final class JitterStatisticsTests: XCTestCase {

    func testEmptySeriesHasNoSamples() {
        let stats = JitterStatistics(deviationsNanoseconds: [])
        XCTAssertEqual(stats.sampleCount, 0)
        XCTAssertEqual(stats.maximumAbsoluteNanoseconds, 0)
        XCTAssertEqual(stats.meanNanoseconds, 0)
        XCTAssertEqual(stats.standardDeviationNanoseconds, 0)
    }

    func testPerfectSeriesHasZeroJitter() {
        let stats = JitterStatistics(deviationsNanoseconds: [0, 0, 0, 0])
        XCTAssertEqual(stats.sampleCount, 4)
        XCTAssertEqual(stats.maximumAbsoluteNanoseconds, 0)
        XCTAssertEqual(stats.meanNanoseconds, 0)
        XCTAssertEqual(stats.standardDeviationNanoseconds, 0)
    }

    func testMeanAndDeviationOnAKnownSeries() {
        // Media 3; desviación típica poblacional = sqrt(2) ≈ 1.4142
        let stats = JitterStatistics(deviationsNanoseconds: [1, 2, 3, 4, 5])
        XCTAssertEqual(stats.sampleCount, 5)
        XCTAssertEqual(stats.meanNanoseconds, 3, accuracy: 0.0001)
        XCTAssertEqual(stats.standardDeviationNanoseconds, 1.414213, accuracy: 0.0001)
    }

    /// El máximo es en valor absoluto: llegar pronto es tan malo como llegar
    /// tarde, y un criterio que solo mirara los retrasos dejaría pasar un
    /// adelanto grave.
    func testMaximumUsesAbsoluteValue() {
        let stats = JitterStatistics(deviationsNanoseconds: [100, -5_000, 200])
        XCTAssertEqual(stats.maximumAbsoluteNanoseconds, 5_000)
    }

    /// La media conserva el signo: un sesgo constante —todo llega 2 ms tarde—
    /// es un problema distinto del jitter y hay que poder distinguirlo.
    func testMeanKeepsSignToRevealConstantBias() {
        let stats = JitterStatistics(deviationsNanoseconds: [-1_000, -1_000, -1_000])
        XCTAssertEqual(stats.meanNanoseconds, -1_000, accuracy: 0.0001)
        XCTAssertEqual(stats.standardDeviationNanoseconds, 0, accuracy: 0.0001)
    }

    func testSingleSampleHasZeroDeviation() {
        let stats = JitterStatistics(deviationsNanoseconds: [42])
        XCTAssertEqual(stats.sampleCount, 1)
        XCTAssertEqual(stats.meanNanoseconds, 42, accuracy: 0.0001)
        XCTAssertEqual(stats.standardDeviationNanoseconds, 0, accuracy: 0.0001)
    }

    // MARK: - Contraste con el umbral del track

    func testStatisticsReportPassAgainstTheTrackThreshold() {
        // Umbral: máx < 2 ms, desviación típica < 0.5 ms.
        let good = JitterStatistics(deviationsNanoseconds: [100_000, -150_000, 90_000])
        XCTAssertTrue(good.meetsTrackThreshold)

        let tooMuchSpread = JitterStatistics(deviationsNanoseconds: [1_000_000, -1_000_000])
        XCTAssertFalse(tooMuchSpread.meetsTrackThreshold)

        let tooLate = JitterStatistics(deviationsNanoseconds: [2_500_000])
        XCTAssertFalse(tooLate.meetsTrackThreshold)
    }
}

/// Tests del registro de muestras.
final class JitterRecorderTests: XCTestCase {

    func testRecorderStartsEmpty() {
        XCTAssertEqual(JitterRecorder(capacity: 10).sampleCount, 0)
    }

    func testRecordedSamplesAreKeptInOrder() {
        let recorder = JitterRecorder(capacity: 10)
        recorder.record(1)
        recorder.record(-2)
        recorder.record(3)
        XCTAssertEqual(recorder.deviations(), [1, -2, 3])
    }

    /// El buffer se preasigna, así que grabar desde el hilo de tiempo real no
    /// puede asignar memoria. Al llenarse, descarta en vez de crecer.
    func testRecorderStopsAtCapacityInsteadOfGrowing() {
        let recorder = JitterRecorder(capacity: 3)
        for value in Int64(1)...Int64(10) { recorder.record(value) }
        XCTAssertEqual(recorder.sampleCount, 3)
        XCTAssertEqual(recorder.deviations(), [1, 2, 3])
    }

    func testRecorderProducesStatistics() {
        let recorder = JitterRecorder(capacity: 5)
        for value in Int64(1)...Int64(5) { recorder.record(value) }
        XCTAssertEqual(recorder.statistics().meanNanoseconds, 3, accuracy: 0.0001)
    }
}
