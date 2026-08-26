import CoreMIDI
import XCTest
@testable import MIDI

/// Tests de la clasificación de resultados de envío.
///
/// La distinción que importa: un dispositivo desconectado no es un fallo del
/// programa, es una situación normal en un secuenciador. Confundir las dos
/// llevaría a mostrar errores alarmantes al desenchufar un cable — justo lo que
/// `product-guidelines.md` prohíbe ("Un dispositivo MIDI desconectado se
/// comunica con un estado, no con una disculpa").
final class MIDISendResultTests: XCTestCase {

    func testNoErrorMeansSent() {
        XCTAssertEqual(MIDISendResult.classify(noErr), .sent)
    }

    func testDisconnectionCodesAreNotTreatedAsFailures() {
        XCTAssertEqual(MIDISendResult.classify(kMIDIObjectNotFound), .destinationUnavailable)
        XCTAssertEqual(MIDISendResult.classify(kMIDIInvalidClient), .destinationUnavailable)
        XCTAssertEqual(MIDISendResult.classify(kMIDIInvalidPort), .destinationUnavailable)
        XCTAssertEqual(MIDISendResult.classify(kMIDIUnknownEndpoint), .destinationUnavailable)
    }

    func testUnexpectedStatusIsReportedAsFailure() {
        XCTAssertEqual(MIDISendResult.classify(-9999), .failed(-9999))
    }
}
