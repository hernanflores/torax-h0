import SwiftUI

@main
struct ToraxH0App: App {

    /// **La fuente se comprueba al arrancar porque su fallo es silencioso.**
    /// Si Figtree no está registrada, iOS cae a la del sistema sin avisar y la
    /// pantalla se ve casi bien. Un aviso por consola convierte eso en algo que
    /// se ve durante el desarrollo, en vez de descubrirse en dispositivo.
    init() {
        if !Typography.isAvailable {
            print("[tipografía] Figtree no está registrada: iOS usará la fuente del sistema.")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
