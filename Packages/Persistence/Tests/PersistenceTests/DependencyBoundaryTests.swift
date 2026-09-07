import XCTest

/// Guarda las dependencias del paquete `Persistence`.
///
/// **La regla que importa es que no dependa de `MIDI`.** Guardar no tiene nada
/// que ver con emitir, y el día que alguien quiera persistir un endpoint o una
/// máscara de mute, la tentación será importar el paquete en vez de traducir el
/// dato a algo que `Engine` sepa nombrar. Este test escanea el fuente en lugar
/// de confiar en la disciplina, igual que hace `Engine` con la stdlib.
///
/// Foundation **sí** está permitido aquí: es la razón de que este paquete
/// exista.
final class DependencyBoundaryTests: XCTestCase {

    private static let forbiddenModules = [
        "AppKit",
        "CoreMIDI",
        "MIDI",
        "SwiftUI",
        "UIKit",
    ]

    private var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PersistenceTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Persistence
            .appendingPathComponent("Sources/Persistence")
    }

    func testPersistenceImportsNeitherMIDINorUI() throws {
        let files = try swiftFiles(in: sourcesDirectory)
        XCTAssertFalse(files.isEmpty, "No se encontró código fuente en \(sourcesDirectory.path)")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for module in Self.forbiddenModules {
                XCTAssertFalse(
                    source.contains("import \(module)"),
                    "\(file.lastPathComponent) importa \(module)"
                )
            }
        }
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard
            let walker = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return [] }

        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
