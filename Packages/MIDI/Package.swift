// swift-tools-version: 6.1
import PackageDescription

/// MIDI — reloj, scheduling y salida CoreMIDI.
///
/// Contiene el camino crítico de timing. Todo código que corra en el hilo del
/// scheduler debe respetar las reglas de tiempo real de
/// `conductor/code_styleguides/swift.md`: sin asignaciones, sin locks, sin
/// `await`, sin logging.
let package = Package(
    name: "MIDI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MIDI", targets: ["MIDI"]),
    ],
    dependencies: [
        .package(path: "../Engine"),
    ],
    targets: [
        // Atómicos sin lock. Target C propio, no una dependencia externa:
        // iPadOS 17 no ofrece alternativa sin recurrir a terceros.
        .target(name: "CToraxAtomics"),
        .target(name: "MIDI", dependencies: ["Engine", "CToraxAtomics"]),
        .testTarget(name: "MIDITests", dependencies: ["MIDI"]),
    ]
)
