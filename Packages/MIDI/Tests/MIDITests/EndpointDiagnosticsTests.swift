import XCTest

@testable import MIDI

/// Tests del informe de diagnóstico de endpoints.
///
/// **Lo que se prueba es el formato, no CoreMIDI.** Leer las propiedades de un
/// endpoint exige un endpoint, y en la máquina de CI no hay ninguno interesante:
/// la sesión de red que este diagnóstico existe para identificar solo aparece en
/// un iPad. Así que la lectura queda en su costura, sin tests, y lo que sí se
/// cubre es que el informe no esconda nada — que es donde un diagnóstico se
/// estropea de verdad.
///
/// **Una propiedad ausente tiene que verse.** Si el informe se saltara las que
/// no están, «esta fuente no declara `driverOwner`» sería indistinguible de «no
/// me acordé de leerlo», y el diagnóstico entero dejaría de servir para decidir.
final class EndpointDiagnosticsTests: XCTestCase {

    // MARK: - Lo que el informe tiene que enseñar

    func testTheReportNamesEverySource() {
        let report = EndpointDiagnostics.report(for: [
            .stub(displayName: "Red Session 1"),
            .stub(displayName: "Arturia BeatStep Pro"),
        ])

        XCTAssertTrue(report.contains("Red Session 1"))
        XCTAssertTrue(report.contains("Arturia BeatStep Pro"))
    }

    func testTheReportCountsTheSources() {
        let report = EndpointDiagnostics.report(for: [
            .stub(displayName: "Red Session 1"),
            .stub(displayName: "Arturia BeatStep Pro"),
        ])

        XCTAssertTrue(report.contains("2"))
    }

    /// **El caso que nadie ve venir**: en el iPad esta lista nunca está vacía, y
    /// eso es justo el defecto. En cualquier otro sitio sí puede estarlo, y un
    /// informe en blanco parecería que el diagnóstico falló.
    func testAnEmptyListSaysSoInsteadOfPrintingNothing() {
        let report = EndpointDiagnostics.report(for: [])

        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(report.lowercased().contains("no sources"))
    }

    // MARK: - Lo ausente se ve

    func testAnAbsentPropertyIsShownAsAbsent() {
        let report = EndpointDiagnostics.report(for: [
            .stub(displayName: "Red Session 1", driverOwner: nil)
        ])

        XCTAssertTrue(report.contains("driverOwner"))
        XCTAssertTrue(report.contains(EndpointDiagnostics.absent))
    }

    /// **Se mira la línea, no el informe entero.** Un stub deja el resto de
    /// campos vacíos a propósito, así que «no aparece `(ausente)` en ninguna
    /// parte» sería falso por razones que no tienen que ver con lo que se prueba.
    func testAPresentPropertyIsShownWithItsValue() {
        let report = EndpointDiagnostics.report(for: [
            .stub(displayName: "Red Session 1", driverOwner: "com.apple.AppleMIDIRTPDriver")
        ])

        let line = report.split(separator: "\n").first { $0.contains("driverOwner") }

        XCTAssertEqual(line?.contains("com.apple.AppleMIDIRTPDriver"), true)
        XCTAssertEqual(line?.contains(EndpointDiagnostics.absent), false)
    }

    /// Las cuatro candidatas que la Fase 1 del track nombra, más el padre. Si
    /// alguna deja de leerse, este test lo dice antes de gastar tiempo de iPad.
    func testEveryCandidateIsLabelled() {
        let report = EndpointDiagnostics.report(for: [.stub(displayName: "Red Session 1")])

        for label in ["driverOwner", "model", "manufacturer", "uniqueID", "entity", "device"] {
            XCTAssertTrue(report.contains(label), "falta la candidata \(label)")
        }
    }

    // MARK: - El volcado entero

    /// **El volcado completo es la red bajo el trapecio.** Las candidatas son
    /// una apuesta; si ninguna distingue, la respuesta está en alguna propiedad
    /// que nadie pensó en pedir, y sin volcado habría que volver al iPad.
    func testTheFullDumpIsIncludedWhenThereIsOne() {
        let report = EndpointDiagnostics.report(for: [
            .stub(displayName: "Red Session 1", allProperties: "{ apple = 1; }")
        ])

        XCTAssertTrue(report.contains("{ apple = 1; }"))
    }

    func testAMissingDumpDoesNotBreakTheReport() {
        let report = EndpointDiagnostics.report(for: [
            .stub(displayName: "Red Session 1", allProperties: nil)
        ])

        XCTAssertTrue(report.contains("Red Session 1"))
    }

    // MARK: - Que se pueda pegar en una git note

    /// El destino de este texto es una git note, y de ahí a este repositorio.
    /// Un informe con líneas de doscientos caracteres se lee mal en los dos
    /// sitios, así que las etiquetas van una por línea.
    func testEachCandidateGoesOnItsOwnLine() {
        let report = EndpointDiagnostics.report(for: [
            .stub(displayName: "Red Session 1", driverOwner: "com.apple.AppleMIDIRTPDriver")
        ])

        let lines = report.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.filter { $0.contains("driverOwner") }.count, 1)
    }
}

extension EndpointProperties {

    /// Un endpoint con lo justo, para no repetir doce campos en cada test.
    fileprivate static func stub(
        displayName: String,
        name: String? = nil,
        model: String? = nil,
        manufacturer: String? = nil,
        driverOwner: String? = nil,
        uniqueID: Int32? = nil,
        isOffline: Bool? = nil,
        hasEntity: Bool = false,
        deviceName: String? = nil,
        deviceDriverOwner: String? = nil,
        allProperties: String? = nil
    ) -> EndpointProperties {
        EndpointProperties(
            displayName: displayName,
            name: name,
            model: model,
            manufacturer: manufacturer,
            driverOwner: driverOwner,
            uniqueID: uniqueID,
            isOffline: isOffline,
            hasEntity: hasEntity,
            deviceName: deviceName,
            deviceDriverOwner: deviceDriverOwner,
            allProperties: allProperties
        )
    }
}
