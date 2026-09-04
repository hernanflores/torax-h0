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

    /// **La sonda de LEDs sustituye a la app entera, no se añade a ella.**
    /// Es instrumentación de la Fase 1 del track `controller-feedback_20260904`
    /// y se borra al cerrarla; colgarla de una pestaña la habría dejado a un
    /// gesto de distancia de alguien tocando, y encima habría que desmontar la
    /// pestaña después. Con el flag no hay nada que desmontar: se quita el
    /// fichero y esta rama.
    var body: some Scene {
        WindowGroup {
            if LEDProbeView.isRequested {
                LEDProbeView()
            } else {
                ContentView()
            }
        }
    }
}
