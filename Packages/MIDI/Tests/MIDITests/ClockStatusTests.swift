import XCTest

@testable import MIDI

/// Tests de qué dice la pantalla sobre el reloj.
///
/// **Bajaron de `App` el 2026-09-06**, en la auditoría de la Fase 4 de
/// `screens-redesign_20260906`. La tabla de cuatro mensajes vivía en
/// `TransportModel`, que está en `App` y no se mide; leía tres estados del
/// `Transport` y decidía cuál contar. Eso es una regla, y una regla mal escrita
/// aquí no falla: enseña el mensaje equivocado, que es peor.
final class ClockStatusTests: XCTestCase {

    // MARK: - Con reloj interno no hay nada que contar

    func testTheInternalClockHasNoStatus() {
        for isPlaying in [true, false] {
            for hasDropped in [true, false] {
                for isEstablished in [true, false] {
                    XCTAssertNil(
                        ClockStatus(
                            source: .internal,
                            isPlaying: isPlaying,
                            hasDropped: hasDropped,
                            isEstablished: isEstablished),
                        "\(isPlaying) \(hasDropped) \(isEstablished)")
                }
            }
        }
    }

    // MARK: - Los cuatro estados del reloj externo

    func testFollowingAMasterWhileItPlays() {
        XCTAssertEqual(status(isPlaying: true, hasDropped: false), .following)
    }

    /// **Perderlo sonando es lo único urgente de los cuatro.** El transporte
    /// sigue con el último tempo conocido en vez de pararse, así que sin este
    /// mensaje la app parecería estar bien mientras se separa del maestro.
    func testLosingTheMasterWhilePlaying() {
        XCTAssertEqual(status(isPlaying: true, hasDropped: true), .lost)
    }

    func testDetectingAMasterBeforeStarting() {
        XCTAssertEqual(status(isPlaying: false, isEstablished: true), .detected)
    }

    func testNoMasterAtAll() {
        XCTAssertEqual(status(isPlaying: false, isEstablished: false), .absent)
    }

    /// Parado, lo que importa es si hay maestro, no si se cayó: `hasDropped`
    /// describe una pérdida en marcha y no dice nada con el transporte quieto.
    func testStoppedTheDropIsIrrelevant() {
        for hasDropped in [true, false] {
            XCTAssertEqual(
                status(isPlaying: false, hasDropped: hasDropped, isEstablished: true), .detected)
        }
    }

    // MARK: - Lo que se escribe

    func testEveryStatusSaysSomething() {
        for status in ClockStatus.allCases {
            XCTAssertFalse(status.description.isEmpty, "\(status)")
        }
    }

    func testTheStatusesReadDifferently() {
        XCTAssertEqual(
            Set(ClockStatus.allCases.map(\.description)).count,
            ClockStatus.allCases.count)
    }

    // MARK: - Helper

    private func status(
        isPlaying: Bool, hasDropped: Bool = false, isEstablished: Bool = false
    ) -> ClockStatus? {
        ClockStatus(
            source: .external,
            isPlaying: isPlaying,
            hasDropped: hasDropped,
            isEstablished: isEstablished)
    }
}
