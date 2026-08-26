// swift-tools-version: 6.1
import PackageDescription

/// Engine — motor generativo puro.
///
/// Este paquete NO debe depender de CoreMIDI, SwiftUI, UIKit ni de ninguna
/// otra librería de plataforma: solo de la stdlib de Swift. Ver
/// `conductor/code_styleguides/swift.md`.
let package = Package(
    name: "Engine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Engine", targets: ["Engine"]),
    ],
    targets: [
        .target(name: "Engine"),
        .testTarget(name: "EngineTests", dependencies: ["Engine"]),
    ]
)
