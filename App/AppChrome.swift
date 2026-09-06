import SwiftUI

/// Los cuatro módulos de la app.
///
/// **Los cuatro existen.** Hasta el 2026-09-06 la navegación dibujaba dos
/// pestañas con borde discontinuo —el signo de «no disponible»— porque Banks y
/// la lista de Tracks no estaban hechas. Ya no: el rediseño las construye, así
/// que el signo se retira en vez de quedarse como decoración.
///
/// **Sin prefijo numérico.** Se llamaban `1 · Track`, `2 · Scale`, `3 · MIDI`,
/// que ordenaba una lista de rebanadas pendientes, no de módulos. El handoff los
/// nombra por lo que son.
enum Module: String, CaseIterable, Identifiable {
    case track
    case scale
    case midi
    case banks

    var id: String { rawValue }

    /// El nombre tal y como se dibuja. Ya en minúsculas por construcción.
    var title: String { rawValue }
}

/// La barra superior, compartida por las cuatro pantallas.
///
/// De izquierda a derecha, como el handoff: el nombre de la app, el módulo
/// activo centrado, el estado de la entrada MIDI, la fuente de reloj, el tempo y
/// el transporte.
///
/// > **El nombre de la app vuelve, y hay que decirlo porque se quitó a
/// > propósito.** El 2026-09-01 se retiró de la interfaz con una razón escrita:
/// > el handoff de entonces no lo dibujaba en ninguna de sus cinco pantallas, y
/// > la app informa en vez de presentarse. El handoff de iPadOS **sí lo dibuja**,
/// > en las cuatro, y es lo primero de la barra. Vuelve por eso, no por
/// > decoración: es el ancla izquierda contra la que se centra el módulo activo.
///
/// **La barra no es una superficie propia.** Antes tenía su propio fondo; en el
/// handoff es el mismo suelo de la página separado por un trazo inferior. Ese
/// cambio es lo que dejó a `Palette.toolbar` sin su primer papel y lo convirtió
/// en `onAccent`.
struct AppChrome: View {

    let model: TransportModel

    /// Qué módulo se está mirando. Solo para escribirlo en el centro: la barra
    /// no navega, de eso se ocupa `ModuleNavigation`.
    let module: Module

    /// **Alto fijo, y por eso es una constante compartida.** La pantalla `track`
    /// calcula el lado del anillo restando lo que no le toca, así que necesita
    /// este número; leerlo de un `GeometryReader` sería circular.
    static let height: CGFloat = 56

    var body: some View {
        ZStack {
            // **El módulo activo se centra contra la pantalla, no contra sus
            // vecinos.** Puesto dentro del `HStack` quedaría empujado por el
            // ancho del bloque de estado, que cambia con el nombre del
            // dispositivo: el título bailaría al enchufar un cable.
            Text(display: module.title)
                .font(Typography.moduleTitle)
                .foregroundStyle(Palette.text)

            HStack(spacing: 20) {
                Text(display: "torax h-0")
                    .font(Typography.moduleTitle)
                    .foregroundStyle(Palette.text)

                Spacer(minLength: 12)

                inputStatus

                outputWarning

                clockSource

                tempo

                transport
            }
        }
        .frame(height: Self.height)
        .padding(.horizontal, 24)
        .background(Palette.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: Brutalist.stroke)
        }
    }

    // MARK: - Estado MIDI

    /// El punto y el nombre de la entrada: `midi: beatstep pro`.
    ///
    /// **Estado, nunca disculpa** (`product-guidelines.md`). Sin controlador el
    /// punto se apaga y el texto dice qué falta; no hay excusa ni consejo.
    private var inputStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isReadOnly ? Palette.border : Palette.shape)
                .frame(width: 10, height: 10)

            Text(display: "midi: \(model.sourceStatus)")
                .font(Typography.caption)
                .foregroundStyle(model.isReadOnly ? Palette.muted : Palette.mutedBright)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        // **El nombre de un endpoint de CoreMIDI puede ser larguísimo**, y sin
        // techo empujaba la barra hasta cortarla por el borde. El estado cede
        // primero: es lo único de esta fila que se puede acortar sin perder una
        // función.
        .frame(maxWidth: 260, alignment: .leading)
    }

    /// El destino de salida **solo cuando falta** (FR6).
    ///
    /// La selección de destino vive en la pantalla `midi`, que es donde el
    /// handoff la pone. Pero sin destino el transporte no puede sonar, y eso hay
    /// que verlo desde cualquiera de las cuatro pantallas: enterarse de que no
    /// hay salida pulsando Play y no oír nada es peor interfaz que un aviso.
    ///
    /// Cuando hay destino no se escribe nada. Repetir el nombre del sinte en la
    /// barra sería el ruido que el handoff quitó de aquí a propósito.
    @ViewBuilder
    private var outputWarning: some View {
        if let unavailable = model.outputUnavailable {
            Text(display: unavailable)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        } else if !model.selection.hasEndpoint {
            Text(display: model.destinationStatus)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
    }

    // MARK: - Reloj

    /// Quién manda el tempo: `internal` o `external`.
    ///
    /// Es lectura, no control. El segmentado que lo cambia vive en la pantalla
    /// `midi`, como en el handoff.
    private var clockSource: some View {
        Text(display: model.followsExternalClock ? "external" : "internal")
            .font(Typography.caption)
            .foregroundStyle(Palette.mutedBright)
    }

    /// El tempo, y el sitio donde se edita (FR5).
    ///
    /// **Se repregunta cuatro veces por segundo, y por eso hay un
    /// `TimelineView`.** El tempo de un maestro externo lo escribe el hilo de
    /// recepción de CoreMIDI, que no puede saltar al principal a avisar —eso
    /// metería la cola del principal en la estimación—, así que no hay estado
    /// observable que cambie y SwiftUI no tendría motivo para repintar.
    ///
    /// **No contradice la regla del playhead.** Lo que `product-guidelines.md`
    /// llama antipatrón es animar con un temporizador algo que debería derivar
    /// del reloj musical; esto no anima nada: relee un valor. Cuatro veces por
    /// segundo es lento para el ojo y sobra para un número.
    private var tempo: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            Button {
                isAdjustingTempo = true
            } label: {
                Text(display: formattedTempo)
                    .font(Typography.captionStrong)
                    .monospacedDigit()
                    .foregroundStyle(
                        model.followsExternalClock ? Palette.groove : Palette.mutedBright
                    )
            }
            .buttonStyle(.plain)
            // **Con reloj externo el número es lectura.** El tempo lo pone el
            // maestro; ofrecer un ajuste que el siguiente tick va a pisar sería
            // un control que miente.
            .disabled(model.followsExternalClock)
            .popover(isPresented: $isAdjustingTempo, arrowEdge: .bottom) {
                TempoAdjuster(model: model)
            }
        }
    }

    @State private var isAdjustingTempo = false

    /// **El punto decimal no depende del locale.** La interfaz va en inglés y
    /// sin traducir; interpolar un `Double` daba `124,0` en un iPad en español,
    /// que es la mitad del texto en un idioma y la otra mitad en otro.
    private var formattedTempo: String {
        String(
            format: "%.0f bpm",
            locale: Locale(identifier: "en_US_POSIX"),
            model.beatsPerMinute
        )
    }

    // MARK: - Transporte

    /// Si el botón hace algo ahora mismo.
    ///
    /// Se puede parar siempre que esté sonando, y arrancar solo si hay destino.
    private var canTransport: Bool { model.canPlay || model.isPlaying }

    /// El control más grande de la barra, porque se toca de pie y de lejos.
    ///
    /// **Sonando es un bloque de off-white; parado es un contorno.** Es la misma
    /// gramática que el resto del sistema —lo elegido se rellena, lo demás lleva
    /// trazo— aplicada al único control que no pertenece a ninguna familia.
    private var transport: some View {
        Button {
            model.isPlaying ? model.stop() : model.play()
        } label: {
            Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 18))
                .foregroundStyle(transportGlyph)
                .frame(width: 72, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!canTransport)
        .brutalistControl(
            accent: Palette.offWhite,
            isSelected: model.isPlaying,
            isPopulated: canTransport
        )
    }

    private var transportGlyph: Color {
        if model.isPlaying { return Palette.onAccent }
        return canTransport ? Palette.offWhite : Palette.muted
    }
}

/// El ajuste del tempo interno.
///
/// **El handoff no lo dibuja, y aun así tiene que existir.** Sus cinco pantallas
/// enseñan `124 bpm` como lectura en la barra y `internal clock · 124 bpm` en la
/// pantalla `midi`, sin un solo control que lo cambie. Entregar eso literalmente
/// dejaría el tempo interno fijo en el valor de arranque, que es una regresión
/// funcional y no una decisión de diseño.
///
/// **Va colgado del número y no suelto en la barra** porque el chrome del
/// handoff es escueto a propósito: dos botones `−` / `+` permanentes ahí arriba
/// serían dos controles compitiendo con el transporte en la fila que se lee de
/// reojo mientras se toca.
private struct TempoAdjuster: View {

    let model: TransportModel

    var body: some View {
        HStack(spacing: 16) {
            step(-1, symbol: "minus")

            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Text(
                    String(
                        format: "%.0f bpm",
                        locale: Locale(identifier: "en_US_POSIX"),
                        model.beatsPerMinute
                    )
                )
                .font(Typography.valueTitle)
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .frame(minWidth: 110)
            }

            step(1, symbol: "plus")
        }
        .padding(20)
        .background(Palette.background)
        .presentationCompactAdaptation(.popover)
    }

    /// Un escalón de un BPM.
    ///
    /// **Uno, no cinco.** `Transport.setTempo` acota a 20–300 y devuelve `false`
    /// fuera de rango, así que los extremos se defienden solos; lo que decide el
    /// tamaño del paso es que ajustar a mano un tempo es afinar, no barrer.
    private func step(_ delta: Double, symbol: String) -> some View {
        Button {
            model.setTempo(model.beatsPerMinute + delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Palette.text)
                .frame(width: 56, height: 44)
        }
        .buttonStyle(.plain)
        .brutalistControl(accent: Palette.offWhite, isSelected: false, isPopulated: true)
    }
}
