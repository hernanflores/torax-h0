import XCTest

@testable import Engine

/// Tests de las doce teclas de la pantalla de Scale & Root.
///
/// **Qué notas están en la escala y cuál es la raíz salen del marco tonal, no de
/// la vista** (`workflow.md`): una tecla mal clasificada se dibuja igual de bien,
/// así que la clasificación se fija donde hay tests.
final class TonalKeyboardTests: XCTestCase {

    // MARK: - Las doce

    /// **Doce teclas, siempre.** Las de fuera de la escala se dibujan cortas y
    /// oscuras, pero se dibujan: si aparecieran y desaparecieran, las demás se
    /// moverían de sitio al cambiar de escala — el mismo criterio que el de los
    /// dieciséis anillos.
    func testThereAreTwelveKeysWhateverTheScale() {
        for scale in Scale.allCases {
            let keyboard = TonalKeyboard(frame: TonalFrame(scale: scale, root: .c))
            XCTAssertEqual(keyboard.keys.count, 12, "\(scale)")
        }
    }

    func testKeysAreInPitchClassOrder() {
        let keys = TonalKeyboard(frame: TonalFrame(scale: .minor, root: .c)).keys

        XCTAssertEqual(keys.map(\.pitchClass), Array(0..<12))
        XCTAssertEqual(keys.map(\.name).first, "C")
        XCTAssertEqual(keys.map(\.name).last, "B")
    }

    // MARK: - Qué está dentro

    /// Do menor: C D D# F G G# A#. Es el registro canónico de `Scale`, visto
    /// desde la pantalla.
    func testCMinorHasItsSevenDegreesInScale() {
        let keyboard = TonalKeyboard(frame: TonalFrame(scale: .minor, root: .c))

        XCTAssertEqual(
            keyboard.keys.filter(\.isInScale).map(\.name),
            ["C", "D", "D#", "F", "G", "G#", "A#"])
    }

    /// **La escala se transpone con el Root**, que es lo que la Pre Spec dice
    /// que el Root hace. Sol menor son las mismas distancias desde G.
    func testTheScaleTransposesWithTheRoot() {
        let keyboard = TonalKeyboard(frame: TonalFrame(scale: .minor, root: Root(7)!))

        XCTAssertEqual(
            keyboard.keys.filter(\.isInScale).map(\.name),
            ["C", "D", "D#", "F", "G", "A", "A#"])
    }

    /// La pentatónica tiene cinco, así que sobran más teclas cortas. Es el mismo
    /// hueco que deja pads sin altura, y se ve igual de explícito.
    func testAPentatonicLeavesMoreKeysOutside() {
        let keyboard = TonalKeyboard(frame: TonalFrame(scale: .pentatonic, root: .c))

        XCTAssertEqual(keyboard.keys.filter(\.isInScale).count, 5)
        XCTAssertEqual(keyboard.keys.filter { !$0.isInScale }.count, 7)
    }

    // MARK: - La raíz

    /// **La raíz es exactamente una**, y no es lo mismo que «está en la escala»:
    /// es la confusión que el handoff se molesta en señalar, y por eso viaja
    /// como una propiedad propia y no como «la primera que esté dentro».
    func testExactlyOneKeyIsTheRoot() {
        for pitchClass in 0..<12 {
            let keyboard = TonalKeyboard(frame: TonalFrame(scale: .major, root: Root(pitchClass)!))
            let roots = keyboard.keys.filter(\.isRoot)

            XCTAssertEqual(roots.count, 1, "root \(pitchClass)")
            XCTAssertEqual(roots.first?.pitchClass, pitchClass)
        }
    }

    /// La raíz siempre está dentro de su propia escala —el grado 1 es el 0 por
    /// definición— pero no todas las que están dentro son la raíz.
    func testTheRootIsAlwaysInItsOwnScaleAndTheOthersAreNot() {
        let keyboard = TonalKeyboard(frame: TonalFrame(scale: .minor, root: Root(3)!))

        let root = keyboard.keys.first { $0.isRoot }
        XCTAssertEqual(root?.name, "D#")
        XCTAssertTrue(root?.isInScale == true)

        let inScaleButNotRoot = keyboard.keys.filter { $0.isInScale && !$0.isRoot }
        XCTAssertEqual(inScaleButNotRoot.count, 6)
    }

    // MARK: - Elegir raíz

    /// **Las doce pueden ser raíz, estén o no en la escala vigente.**
    ///
    /// El handoff dibuja las de fuera como no interactivas, y aquí no se sigue:
    /// sería una confusión de categorías. «¿Está C# en Do menor?» es una
    /// pregunta sobre el marco *actual*; elegir C# como raíz construye un marco
    /// *nuevo* en el que C# es la fundamental y está dentro por definición. Si
    /// las de fuera no se pudieran tocar, qué raíces son alcanzables dependería
    /// de la escala vigente y cambiar de tonalidad sería un rodeo distinto según
    /// dónde se esté — «de una manera que no se puede aprender», que es lo que
    /// la Pre Spec reprocha al mecanismo que descartó.
    func testEveryKeyCanBecomeTheRootIncludingOnesOutsideTheCurrentScale() {
        let cMinor = TonalKeyboard(frame: TonalFrame(scale: .minor, root: .c))
        let cSharp = cMinor.keys[1]

        XCTAssertFalse(cSharp.isInScale, "C# no está en Do menor")
        XCTAssertTrue(cSharp.canBecomeRoot, "y aun así tiene que poder ser raíz")
        XCTAssertTrue(cMinor.keys.allSatisfy(\.canBecomeRoot))
    }

    // MARK: - La línea de estado

    func testTheStatusLineNamesTheScaleAndTheRoot() {
        XCTAssertEqual(
            TonalKeyboard(frame: TonalFrame(scale: .dorian, root: Root(2)!)).statusLine,
            "Scale · Dorian   Root · D")
    }
}
