// swift-tools-version: 6.1
import PackageDescription

/// Persistence — el disco.
///
/// **Existe porque el disco no cabe en los tres paquetes que había.** `Engine`
/// no importa nada fuera de la stdlib —`DependencyBoundaryTests` lo vigila— y
/// `JSONEncoder` es Foundation; `MIDI` es CoreMIDI y guardar no tiene nada que
/// ver con emitir; y `App` no se mide, así que dejar ahí el guardado habría
/// dejado sin cobertura la única pieza capaz de **perder el trabajo del
/// usuario**.
///
/// El reparto con `Engine`: allí viven los DTO `Codable` y la traducción desde y
/// hacia los POD; aquí el encoder, la atomicidad, el debounce del Autosave y el
/// rescate de ficheros ilegibles.
///
/// Umbral de cobertura: **≥90%**, como `Engine`. Ver `conductor/workflow.md`.
let package = Package(
    name: "Persistence",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../Engine")
    ],
    targets: [
        .target(name: "Persistence", dependencies: ["Engine"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
