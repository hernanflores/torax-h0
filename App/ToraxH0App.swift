import MIDI
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

        // **El diagnóstico de la Fase 2 de `midi-learn_20260908`.** iPadOS
        // publica siempre la sesión de red como fuente y la app la
        // autoselecciona; identificarla por el nombre visible está descartado,
        // así que hace falta saber qué propiedad la distingue de verdad.
        //
        // **Se imprime una vez, al arrancar, y solo en Debug.** Las fuentes
        // aparecen y desaparecen al conectar hardware, así que una pasada
        // retrata el momento del arranque: para ver los dos casos se lanza dos
        // veces, con el controlador conectado y sin él. Un aviso por cada cambio
        // de la lista sería ruido en la consola durante el resto del desarrollo.
        #if DEBUG
            print("[midi] --- diagnóstico de fuentes ---")
            print(EndpointDiagnostics.reportForSystemSources())
        #endif
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
                // **La vía de vuelta de la adopción, a ritmo de cuadro.**
                //
                // El hilo del scheduler adopta el Pattern armado en el límite de
                // compás y lo único que publica es una palabra atómica; llamar
                // hacia el modelo desde ahí sería trabajo en el camino de tiempo
                // real. Así que se pregunta, con el mismo criterio que el
                // playhead: lo que suena entra exacto en el compás y lo que la
                // pantalla refleja llega hasta un cuadro después.
                //
                // **Aquí y no dentro del `TimelineView`** aunque FR9 diga «al
                // dibujar»: aplicar escribe en el modelo, y escribir mientras
                // SwiftUI evalúa un cuerpo es invalidar la vista que se está
                // dibujando. La propiedad que FR9 protege —que el hilo de tiempo
                // real no llame a nadie— se cumple igual preguntando desde aquí.
                // Nota fechada del 2026-09-08 en el `spec.md` del track.
                //
                // Sin nada pendiente cuesta una lectura atómica y una
                // comparación, que es lo que pasa en casi todos los cuadros.
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(16))
                        model.applyPendingAdoption()
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
