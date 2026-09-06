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
        // **Tres columnas, y las dos de fuera se reparten el sobrante a
        // partes iguales.** Así el módulo activo cae en el centro de la pantalla
        // sin que el título y el estado puedan solaparse.
        //
        // > **Era un `ZStack` y se veía mal en la primera captura.** El título
        // > flotaba centrado sobre un `HStack` que ocupaba el ancho entero, así
        // > que `track` se dibujaba encima de `midi: no midi input`: dos textos
        // > pisándose. Centrar contra la pantalla y no contra los vecinos sigue
        // > siendo lo correcto —si no, el título bailaría al enchufar un cable—
        // > pero se consigue repartiendo el espacio, no superponiendo.
        HStack(spacing: 20) {
            HStack {
                Text(display: "torax h-0")
                    .font(Typography.moduleTitle)
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(display: module.title)
                .font(Typography.moduleTitle)
                .foregroundStyle(Palette.text)
                .fixedSize()

            HStack(spacing: 20) {
                Spacer(minLength: 0)

                inputStatus

                outputWarning

                clockSource

                tempo

                transport
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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
        Text(display: model.clockSourceName)
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
    ///
    /// > **Era un `popover` y se descartó en la verificación de la Fase 1.** Dos
    /// > razones, y la segunda basta por sí sola:
    /// >
    /// > 1. **Se recortaba.** El número está pegado al borde derecho de la
    /// >    barra, no cabía a su lado, y el sistema lo cortaba en vez de moverlo.
    /// >    Estrecharlo lo mejoró y no lo resolvió.
    /// > 2. **Traía chrome ajeno.** Un popover llega con su contenedor
    /// >    redondeado, su sombra difuminada y su flecha — tres cosas que el
    /// >    lenguaje visual prohíbe por su nombre. Estaba metiendo por la puerta
    /// >    de atrás justo lo que FR2 deja fuera.
    /// >
    /// > Desplegarlo en línea no tiene ninguno de los dos problemas y conserva lo
    /// > que motivó el popover: que no haya dos botones permanentes compitiendo
    /// > con el transporte en la fila que se lee de reojo mientras se toca.
    @ViewBuilder
    private var tempo: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(spacing: 8) {
                if isAdjustingTempo {
                    tempoStep(-1, symbol: "minus")
                }

                Button {
                    // **Con reloj externo no despliega nada.** El tempo lo pone
                    // el maestro; ofrecer un ajuste que el siguiente tick va a
                    // pisar sería un control que miente.
                    guard !model.followsExternalClock else { return }
                    isAdjustingTempo.toggle()
                } label: {
                    Text(display: model.tempoDescription)
                        .font(Typography.captionStrong)
                        .monospacedDigit()
                        .foregroundStyle(tempoTint)
                        .frame(minWidth: 68, minHeight: 32)
                        // Mismo motivo que en los escalones: sin esto solo son
                        // tocables las cifras, y el hueco entre ellas y el borde
                        // del hueco reservado no responde.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.followsExternalClock)

                if isAdjustingTempo {
                    tempoStep(1, symbol: "plus")
                }
            }
        }
    }

    /// De qué color va el número.
    ///
    /// El acento de Groove marca que el tempo viene de fuera, que es el mismo
    /// código que la barra ya usaba. Desplegado se aclara a `text` para que se
    /// note cuál de los tres elementos es el valor y cuáles son los botones.
    private var tempoTint: Color {
        if model.followsExternalClock { return Palette.groove }
        return isAdjustingTempo ? Palette.text : Palette.mutedBright
    }

    @State private var isAdjustingTempo = false

    /// Un escalón de un BPM.
    ///
    /// **Uno, no cinco.** `Transport.setTempo` acota a 20–300 y devuelve `false`
    /// fuera de rango, así que los extremos se defienden solos; lo que decide el
    /// tamaño del paso es que ajustar a mano un tempo es afinar, no barrer.
    private func tempoStep(_ delta: Double, symbol: String) -> some View {
        Button {
            model.setTempo(model.beatsPerMinute + delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: Typography.symbolSmall))
                .foregroundStyle(Palette.text)
                .frame(width: 36, height: 32)
                // **Sin esto solo se puede tocar la tinta**, y `minus` es una
                // línea de un punto de grueso contra la cruz de `plus`: el mismo
                // botón, con la mitad del área útil, fallaba la mitad de las
                // veces. Se vio probándolo — el `−` respondía mal y el `+` bien,
                // que es exactamente la forma que tiene este fallo.
                //
                // El relleno y el trazo los pone `brutalistControl` por fuera del
                // `Button`, así que no cuentan como superficie tocable por más
                // que se vean como un botón. Este es el sitio donde se declara
                // que sí lo son.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalistControl(
            accent: Palette.offWhite,
            isSelected: false,
            isPopulated: true,
            radius: Brutalist.radiusSmall
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
                .font(.system(size: Typography.symbol))
                .foregroundStyle(transportGlyph)
                .frame(width: 72, height: 40)
                // El mismo defecto que en los escalones del tempo, y aquí importa
                // más: es el control que se toca de pie y sin mirar. El triángulo
                // ocupa una fracción de sus 72×40, y sin esto el resto del botón
                // no responde aunque se vea como botón.
                .contentShape(Rectangle())
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

/// La navegación persistente: `track`, `scale`, `midi`, `banks`.
///
/// **Las cuatro, siempre visibles y siempre alcanzables** (FR7). Es lo que la
/// pantalla anterior no podía prometer: dibujaba las que faltaban con borde
/// discontinuo —el signo de «existe y todavía no se puede usar»— y era honesto
/// entonces. Ahora las cuatro existen, así que el signo se retira; dejarlo sería
/// convertir en decoración algo que el lenguaje visual usa para informar.
///
/// **El activo lleva un subrayado de 3 pt en off-white, no un relleno.** El
/// resto del sistema marca lo elegido rellenándolo de acento, y aquí no vale:
/// un módulo no pertenece a ninguna familia de parámetros, y rellenarlo de
/// off-white pondría cuatro bloques compitiendo con el patrón, que es el
/// protagonista. El subrayado dice lo mismo gastando una línea.
///
/// **Navegar no toca el reloj** (FR8). Esta vista no conoce el transporte: solo
/// escribe en un binding que vive por encima de las pantallas, así que cambiar
/// de módulo no puede reiniciar nada aunque quisiera. El playhead sigue donde
/// estaba al volver porque el modelo es el mismo objeto.
struct ModuleNavigation: View {

    @Binding var module: Module

    /// **Alto fijo, como el de la barra y por lo mismo:** la pantalla `track`
    /// resta lo que no le toca para saber cuánto le queda al anillo.
    static let height: CGFloat = 60

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Module.allCases) { candidate in
                item(candidate)
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: Brutalist.stroke)
        }
    }

    private func item(_ candidate: Module) -> some View {
        let isActive = candidate == module

        return Button {
            module = candidate
        } label: {
            Text(display: candidate.title)
                .font(isActive ? Typography.navigationItemActive : Typography.navigationItem)
                .foregroundStyle(isActive ? Palette.text : Palette.muted)
                .frame(height: Self.height)
                .padding(.horizontal, 28)
                .overlay(alignment: .bottom) {
                    // **El subrayado se dibuja siempre y se pinta o no.**
                    // Meterlo en un `if` cambiaría la altura del texto al
                    // conmutar —SwiftUI recompone el overlay— y las cuatro
                    // etiquetas darían un salto de un par de puntos cada vez que
                    // se navega. Así solo cambia el color.
                    //
                    // > **Mide la etiqueta, no la columna.** En la primera
                    // > captura el subrayado cruzaba un cuarto de la pantalla
                    // > porque el `frame(maxWidth: .infinity)` estaba debajo de
                    // > él; el handoff lo dibuja algo más ancho que la palabra y
                    // > nada más. La columna sigue siendo el objetivo táctil —eso
                    // > lo da el `contentShape` de fuera—, pero el trazo mide el
                    // > texto.
                    Rectangle()
                        .fill(isActive ? Palette.offWhite : .clear)
                        .frame(height: Brutalist.strokeEmphasis)
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        // **El objetivo táctil es toda la columna**, no la palabra. Se navega de
        // pie y sin mirar de cerca; un objetivo del ancho de `midi` —cuatro
        // caracteres— obligaría a apuntar.
        .contentShape(Rectangle())
    }
}
