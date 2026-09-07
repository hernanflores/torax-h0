import SwiftUI

@main
struct ToraxH0App: App {

    /// El modelo vive aquí y no en `ContentView` para que el ciclo de vida de la
    /// escena pueda alcanzarlo: **al pasar a segundo plano hay que forzar la
    /// escritura pendiente** (FR14), y ahí no hay tiempo de esperar la calma del
    /// debounce.
    @State private var model = TransportModel()

    @Environment(\.scenePhase) private var scenePhase

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
            ContentView(model: model)
                // **Un tick por segundo, no por fotograma.** El Autosave decide
                // por sí solo si toca escribir; esto solo le da ocasión de
                // mirar. Preguntárselo a 60 Hz sería sesenta veces el mismo
                // «todavía no».
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        model.tickAutosave()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // **Segundo plano escribe ya.** Lo que no se escriba aquí se pierde
            // si el sistema mata la app, que es lo normal y no un fallo.
            if phase != .active { model.flushPendingSaves() }
        }
    }
}
