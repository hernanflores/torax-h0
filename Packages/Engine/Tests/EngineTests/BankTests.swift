import XCTest

@testable import Engine

/// **`Pattern` a secas es ambiguo en un target de test.** Los tests corren en
/// macOS y XCTest arrastra `ApplicationServices`, que trae un `Pattern` de
/// Quickdraw. Se cualifica aquí igual que en `PatternTests`.
private typealias Pattern = Engine.Pattern

/// Tests del `Bank`: dieciséis Patterns y un tempo propio.
///
/// **Es el primer nivel del modelo que no cruza al hilo del scheduler**, y eso
/// decide su forma. `Pattern`, `Track` y `Cycle` son POD con almacenamiento
/// inline porque se copian dentro del hilo de audio; el `Bank` no se copia ahí
/// nunca —lo que se publica es un Pattern— así que guarda sus dieciséis en un
/// array normal. Un `Bank` como tupla serían 592 KB de valor moviéndose por la
/// pila sin que nadie lo pida.
///
/// El test que vigila esa frontera es
/// `testTheBankIsNotTrivialAndThePatternStillIs`.
final class BankTests: XCTestCase {

    // MARK: - Dieciséis, siempre, y vacíos

    /// **Dieciséis exactos**: ninguno se crea ni se destruye.
    ///
    /// Es el idioma que el paquete ya usa dos veces —los doce Tracks del
    /// `Pattern` y los dieciséis Cycles del `Track`— y lo que hace que elegir un
    /// Pattern nunca falle ni asigne. **Este es el único sitio donde el número se
    /// escribe**: todo lo demás deriva de `patternCount`.
    func testABankAlwaysHasSixteenPatterns() {
        let bank = Bank()
        XCTAssertEqual(Bank.patternCount, 16)
        for index in 0..<Bank.patternCount {
            XCTAssertNotNil(bank.pattern(at: index), "Pattern \(index + 1)")
        }
    }

    /// Un Bank recién construido no tiene material en ninguno de los dieciséis.
    ///
    /// «Vacío» no es una bandera: es un `Pattern()`, doce Tracks sin pool. El
    /// silencio sale del material, como en todo el resto del motor.
    func testAFreshBankHasSixteenEmptyPatterns() {
        let bank = Bank()
        for index in 0..<Bank.patternCount {
            XCTAssertEqual(bank.pattern(at: index), Pattern(), "Pattern \(index + 1)")
        }
    }

    /// Un índice fuera del rango no existe y no revienta — mismo criterio que
    /// `Pattern.track(at:)` y que un pad fuera de la superficie.
    func testAnIndexOutsideTheBankHasNoPattern() {
        let bank = Bank()
        let outside = [
            -1, -100, Bank.patternCount, Bank.patternCount + 1, 128, Int.max, Int.min,
        ]
        for index in outside {
            XCTAssertNil(bank.pattern(at: index), "\(index)")
        }
    }

    // MARK: - El tempo es del Bank

    /// La Pre Spec: «16 Banks (cada uno guarda tempo)».
    ///
    /// Arranca en 120 BPM, que es el tempo con el que la app ha arrancado desde
    /// la rebanada 1.
    func testAFreshBankRunsAtOneHundredAndTwentyBeatsPerMinute() {
        XCTAssertEqual(Bank().tempo, Tempo(beatsPerMinute: 120)!)
    }

    /// Cambiar el tempo no toca el material: son dos cosas que viven en el mismo
    /// contenedor y no se rozan.
    func testChangingTheTempoKeepsTheSixteenPatterns() {
        let material = Pattern.initial
        let bank = Bank().replacing(material, at: 3)
        let faster = bank.withTempo(Tempo(beatsPerMinute: 174)!)

        XCTAssertEqual(faster.tempo, Tempo(beatsPerMinute: 174)!)
        for index in 0..<Bank.patternCount {
            XCTAssertEqual(
                faster.pattern(at: index), bank.pattern(at: index), "Pattern \(index + 1)")
        }
    }

    // MARK: - Sustituir uno no toca los otros quince

    func testReplacingAPatternChangesOnlyThatOne() {
        let bank = Bank().replacing(Pattern.initial, at: 5)

        XCTAssertEqual(bank.pattern(at: 5), Pattern.initial)
        for index in 0..<Bank.patternCount where index != 5 {
            XCTAssertEqual(bank.pattern(at: index), Pattern(), "Pattern \(index + 1)")
        }
    }

    /// Sustituir en cada uno de los dieciséis huecos aterriza donde dice.
    ///
    /// Recorre los dieciséis a propósito: si algún día el almacenamiento cambia
    /// de forma, un error de índice se vería aquí y no en el hueco doce.
    func testEveryOneOfTheSixteenSlotsCanHoldMaterial() {
        for slot in 0..<Bank.patternCount {
            let bank = Bank().replacing(Pattern.initial, at: slot)
            XCTAssertEqual(bank.pattern(at: slot), Pattern.initial, "hueco \(slot + 1)")
        }
    }

    /// Fuera de rango devuelve el Bank tal cual: no hay nada que cambiar y no es
    /// un error, con el mismo criterio que `Pattern.replacing(_:at:)`.
    func testReplacingOutsideTheBankReturnsItUnchanged() {
        let bank = Bank().replacing(Pattern.initial, at: 2)
        for index in [-1, Bank.patternCount, Int.max] {
            XCTAssertEqual(bank.replacing(Pattern(), at: index), bank, "\(index)")
        }
    }

    /// El tempo sobrevive a sustituir un Pattern. Es la otra mitad de
    /// `testChangingTheTempoKeepsTheSixteenPatterns`, y las dos existen porque
    /// reconstruir un valor a mano es la forma clásica de perder un campo en
    /// silencio — la advertencia que `Cycle.applying(_:to:)` ya lleva escrita.
    func testReplacingAPatternKeepsTheTempo() {
        let bank = Bank().withTempo(Tempo(beatsPerMinute: 90)!)
        XCTAssertEqual(bank.replacing(Pattern.initial, at: 0).tempo, Tempo(beatsPerMinute: 90)!)
    }

    // MARK: - La frontera de tiempo real

    /// **El Bank no es trivial, y el Pattern sigue siéndolo.**
    ///
    /// Se afirman las dos cosas juntas porque la que importa es la relación. La
    /// restricción de tiempo real **no sube de nivel**: lo que cruza al hilo del
    /// scheduler es un Pattern y solo un Pattern, así que el Bank puede usar un
    /// array —y debe, porque una tupla de dieciséis Patterns son ~592 KB por
    /// copia—. Si algún día alguien intenta publicar un Bank en el handoff, este
    /// test es la primera línea que lo explica.
    func testTheBankIsNotTrivialAndThePatternStillIs() {
        XCTAssertTrue(
            _isPOD(Pattern.self), "el Pattern dejó de ser trivial: el handoff depende de ello")
        XCTAssertTrue(_isPOD(Cycle.self), "el Cycle dejó de ser trivial")
        XCTAssertFalse(
            _isPOD(Bank.self), "el Bank no cruza al scheduler y no tiene por qué ser POD")
    }

    /// El Bank es un valor: copiarlo y cambiar la copia no toca el original.
    func testABankIsAValue() {
        let original = Bank().replacing(Pattern.initial, at: 0)
        let edited = original.replacing(Pattern(), at: 0)

        XCTAssertEqual(original.pattern(at: 0), Pattern.initial)
        XCTAssertEqual(edited.pattern(at: 0), Pattern())
        XCTAssertNotEqual(original, edited)
    }
}
