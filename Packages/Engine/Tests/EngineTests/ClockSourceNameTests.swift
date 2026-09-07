import XCTest

@testable import Engine

/// Tests de `ClockSource`, el enum de quién manda el tempo.
///
/// **El tipo vive en `Engine` desde el 2026-09-07** y estos tests llegaron con
/// él, desde `ClockStatusTests` del paquete `MIDI`. Lo que se prueba aquí es lo
/// que el enum es por sí solo; **cómo se comporta el `Transport` según la fuente
/// se sigue probando en `MIDI`**, en `ClockSourceTests`, que es donde está el
/// `Transport`.
final class ClockSourceNameTests: XCTestCase {

    /// El nombre, en el vocabulario de la Pre Spec y sin traducir. Un iPad en
    /// español enseña `Internal` y `External`.
    func testEachSourceHasItsName() {
        XCTAssertEqual(ClockSource.internal.name, "Internal")
        XCTAssertEqual(ClockSource.external.name, "External")
    }

    /// Los dos estados son distintos y ninguno es el otro. Trivial y barato: es
    /// lo que impide que un refactor deje `name` devolviendo la misma cadena.
    func testTheTwoSourcesAreDistinct() {
        XCTAssertNotEqual(ClockSource.internal, ClockSource.external)
        XCTAssertNotEqual(ClockSource.internal.name, ClockSource.external.name)
    }
}
