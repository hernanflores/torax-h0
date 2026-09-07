import Engine
import XCTest

@testable import Persistence

/// Tests de `DiskFileSystem`, contra un disco de verdad.
///
/// **La costura hizo testeable todo menos ella misma.** El resto del paquete se
/// prueba contra el doble en memoria, que es lo correcto —así se provocan disco
/// lleno y escritura interrumpida sin ceremonia— y deja sin ejercitar la única
/// pieza que en producción toca ficheros. Se vio en la cobertura del checkpoint
/// de la Fase 4: `FileSystem.swift` al 0%.
///
/// Corre contra un directorio temporal propio, que se borra al terminar. No es
/// un test lento ni frágil: son cuatro operaciones sobre cuatro ficheros.
final class DiskFileSystemTests: XCTestCase {

    private var root: URL!
    private let files = DiskFileSystem()

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("torax-tests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// Escribir y volver a leer devuelve los mismos bytes.
    func testWhatIsWrittenIsWhatIsRead() throws {
        let url = root.appendingPathComponent("a.json")
        let data = Data("{\"hola\": 1}".utf8)

        try files.write(data, to: url)

        XCTAssertEqual(try files.read(url), data)
    }

    /// **Leer lo que no existe devuelve `nil` y no lanza.** Es el estado de la
    /// primera vez que se abre la app, y tratarlo como error obligaría a
    /// distinguirlo en cada sitio de uso.
    func testReadingAMissingFileIsNilAndNotAnError() throws {
        XCTAssertNil(try files.read(root.appendingPathComponent("no-existe.json")))
    }

    /// Escribir dos veces deja lo último, sin restos de lo anterior.
    func testWritingTwiceLeavesTheSecondOne() throws {
        let url = root.appendingPathComponent("b.json")

        try files.write(Data("primero".utf8), to: url)
        try files.write(Data("segundo".utf8), to: url)

        XCTAssertEqual(try files.read(url), Data("segundo".utf8))
    }

    /// **Crear un directorio crea los intermedios que falten**, que es lo que
    /// permite escribir `banks/bank-01.json` sin haber creado `banks` antes.
    func testCreatingADirectoryMakesTheMissingIntermediateOnes() throws {
        let deep = root.appendingPathComponent("uno/dos/tres", isDirectory: true)

        try files.createDirectory(deep)
        try files.write(Data("x".utf8), to: deep.appendingPathComponent("c.json"))

        XCTAssertEqual(try files.read(deep.appendingPathComponent("c.json")), Data("x".utf8))
    }

    /// Crear un directorio que ya existe no es un error.
    func testCreatingAnExistingDirectoryIsFine() throws {
        XCTAssertNoThrow(try files.createDirectory(root))
    }

    /// Mover conserva el contenido y deja el origen vacío. Es lo que aparta un
    /// fichero ilegible **sin borrarlo**.
    func testMovingKeepsTheContentAndEmptiesTheOrigin() throws {
        let source = root.appendingPathComponent("roto.json")
        let destination = root.appendingPathComponent("roto.20260907.unreadable")
        try files.write(Data("basura".utf8), to: source)

        try files.move(source, to: destination)

        XCTAssertEqual(try files.read(destination), Data("basura".utf8))
        XCTAssertNil(try files.read(source))
    }

    /// Mover lo que no existe lanza. Aquí sí es un error: quien mueve un fichero
    /// acaba de leerlo.
    func testMovingAMissingFileThrows() {
        XCTAssertThrowsError(
            try files.move(
                root.appendingPathComponent("fantasma"),
                to: root.appendingPathComponent("otro")
            )
        )
    }

    /// **Escribir donde no se puede lanza**, en vez de fallar en silencio. Es lo
    /// que hace que el estado de fallo del almacén se ponga.
    func testWritingIntoAMissingDirectoryThrows() {
        let url = root.appendingPathComponent("no/existe/d.json")
        XCTAssertThrowsError(try files.write(Data("x".utf8), to: url))
    }

    /// **El almacén de verdad, contra el disco de verdad, de punta a punta.**
    /// Es el único test del paquete que no usa el doble: si la costura y su
    /// implementación se separaran, se vería aquí.
    func testTheStoreWorksAgainstARealDisk() throws {
        let store = ProjectStore(fileSystem: files, directory: root)
        let project = Project.initial.selectingBank(2).withClockSource(.external)

        try store.save(project)

        XCTAssertEqual(store.load().project, project)
    }
}
