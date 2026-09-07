import Foundation

/// Un reloj que avanza cuando el test lo dice.
///
/// **Es una clase y no una variable local** porque el `Autosave` pide una
/// función `@Sendable`, y una closure `@Sendable` no puede capturar una `var`
/// del test ni al propio `XCTestCase`. Una referencia sí.
///
/// Esto es lo que permite que ningún test del debounce espere segundos de
/// verdad: un test que duerme dos segundos es un test que algún día falla solo
/// en un runner cargado.
final class TestClock: @unchecked Sendable {

    private(set) var seconds: TimeInterval

    init(_ seconds: TimeInterval = 1000) {
        self.seconds = seconds
    }

    /// La función que se le pasa al Autosave.
    var now: @Sendable () -> TimeInterval { { [self] in seconds } }

    func advance(_ interval: TimeInterval) {
        seconds += interval
    }
}
