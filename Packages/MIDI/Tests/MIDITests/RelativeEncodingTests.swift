import XCTest
@testable import MIDI

/// Tests de la decodificación de encoders relativos.
///
/// `product-guidelines.md`: «los encoders operan en modo relativo: incrementan
/// o decrementan desde el valor actual del software. Sin saltos, sin zona muerta
/// de pickup, sin necesidad de alcanzar un valor». El byte que llega no es una
/// posición: es un desplazamiento con signo.
final class RelativeEncodingTests: XCTestCase {

    private let encoding = RelativeEncoding.twosComplement

    // MARK: - Complemento a dos de 7 bits

    func testSmallestIncrement() {
        XCTAssertEqual(encoding.delta(from: 0x01), 1)
    }

    func testLargestIncrement() {
        XCTAssertEqual(encoding.delta(from: 0x3F), 63)
    }

    func testSmallestDecrement() {
        XCTAssertEqual(encoding.delta(from: 0x7F), -1)
    }

    func testLargestDecrement() {
        XCTAssertEqual(encoding.delta(from: 0x41), -63)
    }

    /// El rango entero, byte a byte.
    func testEveryValueDecodesToItsSignedDelta() {
        for value in 1...63 {
            XCTAssertEqual(encoding.delta(from: UInt8(value)), value, "0x\(String(value, radix: 16))")
        }
        for value in 65...127 {
            XCTAssertEqual(
                encoding.delta(from: UInt8(value)),
                value - 128,
                "0x\(String(value, radix: 16))"
            )
        }
    }

    // MARK: - Los dos valores que no mueven nada

    func testZeroDoesNotMove() {
        XCTAssertEqual(encoding.delta(from: 0x00), 0)
    }

    /// **`0x40` es el centro ambiguo.** En complemento a dos estricto valdría
    /// −64, pero muchos controladores lo emiten en reposo. Interpretarlo como el
    /// mayor decremento posible convertiría un knob quieto en un salto brutal,
    /// así que se trata como ausencia de movimiento.
    func testCentreDoesNotMove() {
        XCTAssertEqual(encoding.delta(from: 0x40), 0)
    }

    // MARK: - Robustez

    /// Un byte de datos MIDI nunca supera 127. Si llega uno, no se inventa un
    /// giro: se ignora.
    func testValuesAboveTheMIDIDataRangeAreIgnored() {
        for value in [UInt8(128), 200, 255] {
            XCTAssertEqual(encoding.delta(from: value), 0, "\(value)")
        }
    }

    func testDecodingIsDeterministic() {
        for _ in 0..<100 {
            XCTAssertEqual(encoding.delta(from: 0x02), 2)
            XCTAssertEqual(encoding.delta(from: 0x7E), -2)
        }
    }

    // MARK: - Simetría

    /// Un giro y su contrario se cancelan: es lo que hace que el knob sea
    /// predecible.
    func testOppositeTurnsCancelOut() {
        for magnitude in 1...63 {
            let forward = encoding.delta(from: UInt8(magnitude))
            let backward = encoding.delta(from: UInt8(128 - magnitude))
            XCTAssertEqual(forward + backward, 0, "±\(magnitude)")
        }
    }
}
