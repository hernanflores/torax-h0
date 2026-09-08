import Engine
import SwiftUI

/// La pantalla `modulation`: la forma del movimiento de la velocity y cuánto
/// se desvía (FR10, FR11).
///
/// **Aquí el dedo opera**, como en `scale`, `midi` y `banks`. No contradice al
/// principio rector: lo que `product-guidelines.md` protege es que no haga falta
/// mirar el iPad *para tocar*, y esto se configura antes. La pantalla `track`
/// sigue siendo la que se lee mientras suena, y ahí no se edita nada.
///
/// **Dos columnas, ~70/30 como el handoff** (FR11). A la izquierda lo que se
/// elige —la rejilla de ondas— y lo que se mira —el panel de respuesta—; a la
/// derecha el card alto de `accent` y el resumen al pie.
///
/// **El mauve no es un color nuevo.** `Palette.groove` ya es `#AA6DA8`, y la
/// pantalla lo usa porque **lo que modula es velocity**, que es Groove: el color
/// sigue codificando qué tipo de parámetro se toca, que es lo que
/// `product-guidelines.md` le exige. No se añade un cuarto acento que habría que
/// verificar a un metro.
struct ModulationScreen: View {

    let model: TransportModel

    var body: some View {
        // **~70/30, repartido contra el ancho disponible** (FR11).
        //
        // > **Se intentó con `layoutPriority` y se vio mal en el simulador.** La
        // > prioridad no reparte proporciones: decide **quién pide primero**, así
        // > que la columna izquierda —con `maxWidth: .infinity`— se quedaba con
        // > todo y la derecha bajaba a unos cuarenta puntos, con `accent`
        // > partido en una letra por línea. Una fracción del ancho medido dice
        // > lo que se quería decir; la prioridad decía otra cosa.
        GeometryReader { area in
            let gutter: CGFloat = 24
            let usable = max(area.size.width - gutter, 1)
            columns(left: usable * Self.leftShare, right: usable * (1 - Self.leftShare))
        }
        // El alto lo fija el contenido, no la pantalla: el `GeometryReader` solo
        // se usa para el ancho, y sin esto se comería la altura entera.
        .frame(height: Self.contentHeight)
    }

    /// Alto del contenido de la pantalla.
    ///
    /// Fijo porque el `GeometryReader` de arriba mide el ancho y propondría
    /// altura infinita a sus hijos; la columna izquierda tiene que caber entera
    /// —rejilla más panel— y la derecha se estira hasta donde le den.
    private static let contentHeight: CGFloat = 620

    private func columns(left: CGFloat, right: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                ModulationContext(
                    track: model.selectedTrackIndex,
                    cycle: model.editingCycle
                )

                WaveformSelector(
                    waveform: model.modulation.waveform,
                    onSelect: { model.setModulation(model.modulation.with(waveform: $0)) }
                )

                VelocityResponseView(
                    response: model.track.velocityResponse,
                    waveform: model.modulation.waveform,
                    isPlaying: model.isPlaying,
                    playhead: { model.playheads[safe: model.selectedTrackIndex] ?? nil }
                )

                Spacer(minLength: 0)
            }
            .frame(width: left, alignment: .leading)

            VStack(spacing: 20) {
                AccentCard(
                    accent: model.modulation.accent,
                    onChange: { model.setModulation(model.modulation.with(accent: $0)) }
                )

                ModulationSummaryCard(modulation: model.modulation)

                Spacer(minLength: 0)
            }
            .frame(width: right)
        }
    }

    /// El reparto de FR11: la izquierda se lleva el 70% y la derecha el resto.
    private static let leftShare: CGFloat = 0.7
}

extension Array {

    /// El elemento de esa posición, o `nil` fuera de rango.
    ///
    /// La lista de playheads tiene doce entradas con el transporte corriendo y
    /// puede no tenerlas al arrancar; pedir una fuera de rango no es un error y
    /// no debe reventar la pantalla.
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// De qué Track y de qué Cycle se está editando la modulación (FR16, FR17).
///
/// **Nombra los dos, y no solo el Track.** `modulation` escribe sobre el Cycle
/// **en edición**, que puede no ser el que suena: sin decirlo, editar el B
/// mientras suena el A parece que la pantalla miente.
///
/// **Es una etiqueta y no un selector** (FR17), a diferencia de la de `scale`.
/// El Track se elige con el controlador —el instrumento— y esta pantalla solo lo
/// lee: no lleva la franja de doce. Los dos cursores los mueven los knobs, y
/// duplicar esa vía aquí sería inventar un segundo sitio donde se decide lo
/// mismo.
struct ModulationContext: View {

    let track: Int
    let cycle: Int

    var body: some View {
        Text(display: "track \(Self.two(track + 1)) · cycle \(Self.two(cycle + 1))")
            .font(Typography.caption)
            .foregroundStyle(Palette.mutedBright)
            .monospacedDigit()
    }

    /// Dos cifras, como el handoff: `track 04`, no `track 4`.
    ///
    /// **Con ancho fijo el texto no se mueve** al pasar del Track 9 al 10, que es
    /// lo que se mira de reojo mientras se ajusta.
    private static func two(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }
}

/// La rejilla 2×2 con las cuatro ondas (FR11, FR19).
///
/// **El orden es el de `Waveform.allCases`**, que es parte del contrato del tipo
/// y está fijado por test: `saw`, `triangle`, `sine`, `pulse`.
///
/// **Escribe sobre el Cycle en edición**, y esa regla no vive aquí sino en
/// `ControlInput.setModulation` — donde hay tests. Esta vista solo dice qué onda
/// se ha tocado.
struct WaveformSelector: View {

    let waveform: Waveform
    let onSelect: (Waveform) -> Void

    private static let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display: "waveform")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)

            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(Waveform.allCases, id: \.self) { candidate in
                    WaveformCard(
                        waveform: candidate,
                        isSelected: candidate == waveform,
                        onSelect: { onSelect(candidate) }
                    )
                }
            }
        }
    }
}

/// Una onda de la rejilla: su dibujo y su nombre (FR19, FR20).
///
/// **Seleccionada es un bloque de mauve plano con la etiqueta oscura**; las
/// otras tres van hundidas con borde neutro. Es la misma gramática que el resto
/// del sistema —lo elegido se rellena, lo demás lleva trazo— con el acento de
/// Groove, porque lo que se modula es velocity.
///
/// **El objetivo táctil es el card entero.** Se toca sin mirar de cerca, así que
/// el `contentShape` cubre los 96 puntos de alto y no solo el trazo de la onda.
struct WaveformCard: View {

    let waveform: Waveform
    let isSelected: Bool
    let onSelect: () -> Void

    /// **Alto fijo y generoso.** El dibujo necesita sitio para leerse a un metro
    /// y el card es el objetivo táctil: 96 puntos son más del doble del mínimo
    /// cómodo, que es lo que pide `product-guidelines.md` de algo que se toca de
    /// pie.
    private static let height: CGFloat = 96

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                WaveformPreview(waveform: waveform)
                    .stroke(
                        isSelected ? Palette.onAccent : Palette.mutedBright,
                        style: StrokeStyle(lineWidth: Brutalist.stroke, lineJoin: .round)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)

                Text(display: waveform.description)
                    .font(isSelected ? Typography.bodyStrong : Typography.body)
                    .foregroundStyle(isSelected ? Palette.onAccent : Palette.text)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            // Sin esto solo responden el trazo y las letras, que entre los dos
            // no llegan a la mitad del card. Es el mismo defecto que se corrigió
            // en los escalones del tempo.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalistControl(
            accent: Palette.groove,
            isSelected: isSelected,
            isPopulated: false,
            radius: Brutalist.radius
        )
    }
}

/// El dibujo de una onda: **dos ciclos, trazo geométrico, sin relleno** (FR19).
///
/// **Dos ciclos y no uno**, como el handoff: con uno solo, `saw` y `triangle`
/// se distinguen mal —la diferencia está en el corte, y un corte necesita algo
/// después para leerse como corte—.
///
/// **Sale de `Waveform.value(atStep:of:)`, la misma función que suena.** Podría
/// dibujarse con una fórmula propia y sería más corto; sería también una segunda
/// definición de la forma, capaz de discrepar en silencio de lo que se emite. La
/// resolución del muestreo es cosa del dibujo —64 puntos por ciclo, que a este
/// tamaño es una curva continua— y la forma es la del motor.
///
/// > **Que `saw` se dibuje con su corte en el cuarto y no a media vuelta no es
/// > un error del dibujo.** Es la forma que se entrega, y alinear su pico con el
/// > de las otras tres es lo que hace que cambiar de onda no mueva el acento de
/// > sitio (FR5). El dibujo tiene que enseñar lo que suena.
///
/// > **`SwiftUI.Shape` con el módulo delante, y no por gusto.** `Engine.Shape`
/// > es la familia de Steps, Pulses, Rotate y Division, y este fichero importa
/// > los dos módulos: sin calificar, el nombre es ambiguo. Es el mismo choque
/// > que la suite de `MIDI` resuelve con un `typealias` para `Pattern`.
struct WaveformPreview: SwiftUI.Shape {

    let waveform: Waveform

    /// Cuántos ciclos se dibujan.
    ///
    /// **Dos en el card de la rejilla y uno en el panel**, y la diferencia
    /// importa: el card enseña *qué forma es* —y con un solo ciclo `saw` y
    /// `triangle` se distinguen mal, porque la diferencia está en el corte y un
    /// corte necesita algo después para leerse como tal—; el panel enseña *una
    /// vuelta del anillo*, que es exactamente un ciclo (FR4). Dibujar dos sobre
    /// dieciséis barras diría que la modulación va al doble de velocidad de lo
    /// que va.
    var cycles: Int = 2

    /// Puntos por ciclo. No es un parámetro del dominio: es cuánto se muestrea
    /// para que la línea se vea curva y no escalonada.
    private static let resolution = 64

    /// Cuánto tiene que saltar el valor entre dos muestras vecinas para que el
    /// dibujo lo trate como un corte y no como una pendiente.
    ///
    /// > **Ciento veinte y no «cualquier bajada».** A esta resolución una
    /// > pendiente normal se mueve unas pocas unidades por muestra; los dos
    /// > cortes que existen —el de `saw` y los dos de `pulse`— valen 190 y 200.
    /// > Cualquier número entre medias sirve, y este deja sitio de sobra a los
    /// > dos lados.
    private static let discontinuity = 120

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let total = Self.resolution * cycles

        func point(_ index: Int, _ value: Int) -> CGPoint {
            // La onda va de −100 a 100 y la `y` de una vista crece hacia abajo,
            // así que el signo se invierte: +100 es el borde de arriba.
            CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(total),
                y: rect.midY - rect.height / 2 * CGFloat(value) / 100
            )
        }

        // Un punto extra para cerrar el segundo ciclo en su final, que si no
        // queda un hueco del ancho de una muestra contra el borde derecho.
        var previous = waveform.value(atStep: 0, of: Self.resolution)
        path.move(to: point(0, previous))

        for index in 1...total {
            let value = waveform.value(atStep: index, of: Self.resolution)

            // **Un corte se dibuja vertical, y solo un corte.**
            //
            // > **Se hacía en cada muestra de `saw` y de `pulse`, y se vio en la
            // > primera captura del simulador.** `pulse` salía bien —dos valores,
            // > así que el escalón coincide con la forma— pero `saw` salía como
            // > una escalera dentada en vez de una rampa: el paso horizontal más
            // > vertical se aplicaba también donde la onda solo sube un poco.
            // > Lo que distingue un corte de una pendiente es el tamaño del
            // > salto, no de qué onda se trate.
            if abs(value - previous) >= Self.discontinuity {
                path.addLine(to: point(index, previous))
            }
            path.addLine(to: point(index, value))
            previous = value
        }
        return path
    }
}

/// El card alto de `accent`: la lectura grande, el slider bipolar y su etiqueta
/// (FR11, FR18, FR19).
///
/// **La lectura va arriba y grande**, porque es el valor que se mira al
/// arrastrar. Lleva el signo también en el positivo, y ese formato vive en
/// `Engine` (NFR6): aquí solo se pinta.
struct AccentCard: View {

    let accent: Accent
    let onChange: (Accent) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(display: "accent")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(display: accent.description)
                .font(Typography.readout)
                .monospacedDigit()
                .foregroundStyle(Palette.groove)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            BipolarAccentSlider(accent: accent, onChange: onChange)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220)

            Text(display: "bipolar velocity")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .brutalistPanel()
    }
}

/// El slider bipolar vertical de `accent` (FR18).
///
/// **`+100` arriba, `0` en el centro exacto, `−100` abajo.** El arrastre es
/// continuo y el pulgar sigue al dedo; un toque simple sobre la pista salta a
/// ese valor, que es lo que hace que llegar a un extremo no exija recorrerlo.
///
/// **Se imanta en el 0, y solo en el 0.** Es el único valor que hay que poder
/// recuperar sin mirar —el que apaga la modulación— y el único, por tanto, que
/// merece un enganche. Imantar también los extremos convertiría el ajuste fino
/// cerca de ±100 en saltos.
///
/// > **El imantado vive aquí y no en `Accent`.** Lo que hace que un punto esté
/// > «cerca» del centro son puntos de pantalla, no unidades del parámetro: el
/// > tipo cruza el cero como cualquier otro valor y hay un test que lo fija. Es
/// > la misma frontera que separa el dibujo de la forma de la forma misma.
struct BipolarAccentSlider: View {

    let accent: Accent
    let onChange: (Accent) -> Void

    /// Cuánto se imanta el centro, en puntos de pantalla.
    ///
    /// **Diez puntos**, que sobre una pista de unas doscientas son un 5% del
    /// recorrido a cada lado: bastante para atrapar el dedo sin mirar, poco para
    /// no robar el tramo donde se ajusta un acento suave.
    private static let snapPoints: CGFloat = 10

    /// El ancho de la pista. El pulgar la desborda a los dos lados, que es lo
    /// que lo hace visible sin engordar la pista.
    private static let trackWidth: CGFloat = 12

    private static let thumbWidth: CGFloat = 40
    private static let thumbHeight: CGFloat = 20

    var body: some View {
        GeometryReader { area in
            let height = area.size.height
            let travel = max(height - Self.thumbHeight, 1)
            // El pulgar se mueve dentro del recorrido útil, no de la altura
            // entera: si no, en los extremos se saldría media altura de pulgar.
            let y = Self.thumbHeight / 2 + travel * CGFloat(100 - accent.percent) / 200

            ZStack(alignment: .top) {
                // La pista.
                Capsule()
                    .fill(Palette.inset)
                    .overlay(Capsule().stroke(Palette.border, lineWidth: Brutalist.stroke))
                    .frame(width: Self.trackWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // **La marca del centro, off-white.** Es la referencia del 0 y
                // por eso es lo más claro de la pieza: sin ella, «el pulgar está
                // en medio» sería una impresión y no una lectura.
                Rectangle()
                    .fill(Palette.offWhite)
                    .frame(width: Self.thumbWidth, height: Brutalist.stroke)
                    .frame(maxWidth: .infinity)
                    .offset(y: Self.thumbHeight / 2 + travel / 2)

                // El pulgar, mauve, porque lo que modula es velocity.
                RoundedRectangle(cornerRadius: Brutalist.radiusSmall)
                    .fill(Palette.groove)
                    .overlay(
                        RoundedRectangle(cornerRadius: Brutalist.radiusSmall)
                            .stroke(Palette.groove, lineWidth: Brutalist.stroke)
                    )
                    .frame(width: Self.thumbWidth, height: Self.thumbHeight)
                    .frame(maxWidth: .infinity)
                    .offset(y: y - Self.thumbHeight / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // **Toda la columna responde, no solo la pista de doce puntos.** Es
            // el mismo defecto que se corrigió en los escalones del tempo: un
            // objetivo del ancho de la tinta falla la mitad de las veces.
            .contentShape(Rectangle())
            .gesture(
                // `minimumDistance: 0` es lo que hace que un toque simple sobre
                // la pista salte a ese valor (FR18): sin él, tocar sin arrastrar
                // no produciría ningún evento.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onChange(Self.accent(at: value.location.y, over: height))
                    }
            )
        }
    }

    /// Qué `accent` corresponde a un punto de la pista.
    ///
    /// Arriba es `+100` y abajo `−100`, así que la escala se invierte respecto
    /// de la `y` de la vista.
    private static func accent(at y: CGFloat, over height: CGFloat) -> Accent {
        let travel = max(height - thumbHeight, 1)
        let position = min(max(y - thumbHeight / 2, 0), travel)
        let percent = Int((0.5 - position / travel) * 200)

        // El imantado, traducido de puntos de pantalla a unidades del parámetro
        // sobre esta pista concreta — que es la razón por la que vive aquí.
        let snapWidth = Int(snapPoints / travel * 200)
        let snapped = abs(percent) <= snapWidth ? 0 : percent

        return Accent(percent: min(max(snapped, -100), 100)) ?? .default
    }
}

/// El panel `velocity response`: lo que se va a emitir, barra a barra (FR12–FR15).
///
/// **La altura de cada barra es la velocity final, recorte incluido** (FR12), y
/// no la forma normalizada: dos ajustes que recortan distinto se tienen que ver
/// distintos. El dato sale de `Cycle.velocityResponse`, que vive en `Engine` y
/// está probado con números.
///
/// **Tantas barras como Steps tenga el Track** (FR13). El 16 del handoff es el
/// caso por defecto, no una constante.
///
/// **El playhead cae sobre la barra que suena y desaparece con el transporte
/// parado** (FR14). Las barras se quedan: son estado, no animación.
struct VelocityResponseView: View {

    let response: [VelocityResponseStep]
    let waveform: Waveform

    /// Si el transporte está corriendo. Para el redibujado cuando no lo está.
    let isPlaying: Bool

    /// Dónde está el tiempo, o `nil` con el transporte parado.
    ///
    /// > **Es un cierre y no un valor, y esa es la corrección del 2026-09-08.**
    /// > Se entregó como valor y **el playhead no se movía** — lo encontró la
    /// > verificación en dispositivo, que es el único sitio donde se puede ver:
    /// > el simulador no tiene destinos MIDI, así que ahí no hay transporte que
    /// > lo mueva y el defecto era invisible.
    /// >
    /// > La causa: `TransportModel.playheads` **no es estado observable y no debe
    /// > serlo** —cambia de forma continua, y publicarlo obligaría a invalidar la
    /// > vista entera a 60 Hz—. Se consulta al dibujar, y quien lo dibuja tiene
    /// > que provocar su propio redibujado. El anillo lo hace desde hace tiempo
    /// > con un `TimelineView`; este panel leía el valor una sola vez, al
    /// > construir el cuerpo, y no volvía a preguntar.
    let playhead: () -> Playhead?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(display: "velocity response")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)

            GeometryReader { area in
                ZStack(alignment: .bottom) {
                    // **La línea de centro va DETRÁS de las barras.**
                    //
                    // > Estaba delante y se vio en el simulador: cruzaba las
                    // > barras por la mitad y parecía que cada una estaba
                    // > partida en dos. Es una referencia para leer la onda, no
                    // > un dato — y lo que no es dato no tapa al dato.
                    Rectangle()
                        .fill(Palette.border)
                        .frame(height: Brutalist.stroke)
                        .offset(y: -area.size.height / 2)

                    bars(in: area.size)

                    // La onda seleccionada, **un solo ciclo**: el panel dibuja
                    // una vuelta del anillo, y una vuelta es un ciclo (FR4).
                    WaveformPreview(waveform: waveform, cycles: 1)
                        .stroke(Palette.groove, lineWidth: Brutalist.stroke)
                        .frame(width: area.size.width, height: area.size.height)

                    // **Solo el playhead se repinta al ritmo de la pantalla.**
                    // Las barras se quedan fuera del `TimelineView` a propósito:
                    // son estado y no animación (FR14), y meterlas dentro
                    // reconstruiría dieciséis vistas por fotograma para dibujar
                    // exactamente lo mismo.
                    //
                    // **No es un temporizador nuevo**: es el mismo mecanismo que
                    // el playhead del anillo, que ya existe y ya está medido, y
                    // que se detiene solo con el transporte parado.
                    TimelineView(.animation(paused: !isPlaying)) { _ in
                        playheadMark(in: area.size)
                    }
                }
            }
            .frame(height: 180)
            .padding(12)
            .brutalistPanel()

            Text(display: "1 cycle per pattern")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    /// Una barra por Step, con la altura de su velocity.
    ///
    /// **Los que no son pulso van atenuados** (FR13, FR8): el LFO corre sobre
    /// ellos, así que tienen valor y no suenan. Omitirlos mentiría sobre la fase.
    private func bars(in size: CGSize) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(response.enumerated()), id: \.offset) { index, entry in
                RoundedRectangle(cornerRadius: Brutalist.radiusSmall)
                    .fill(entry.triggers ? Palette.offWhite : Palette.stepDim)
                    .frame(
                        height: max(
                            size.height * CGFloat(entry.velocity.value)
                                / CGFloat(Velocity.validRange.upperBound),
                            Brutalist.stroke
                        )
                    )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
    }

    /// El playhead: una línea vertical sobre la barra que suena.
    ///
    /// **Un redibujo por Step**, la misma cadencia que el playhead del anillo:
    /// esta vista no tiene temporizador propio, se repinta cuando el modelo
    /// publica. Con el transporte parado no se dibuja.
    @ViewBuilder
    private func playheadMark(in size: CGSize) -> some View {
        if let playhead = playhead(), !response.isEmpty {
            let step = playhead.step % response.count
            let width = size.width / CGFloat(response.count)
            Rectangle()
                .fill(Palette.offWhite)
                .frame(width: Brutalist.strokeEmphasis, height: size.height)
                .offset(x: -size.width / 2 + width * (CGFloat(step) + 0.5))
        }
    }

}

/// El card resumen al pie de la columna derecha (FR11, FR19).
///
/// Dice lo mismo que la pantalla ya enseña, en dos líneas y sin dibujo: es la
/// lectura que se busca de reojo para confirmar qué está puesto, no otra vía de
/// edición.
struct ModulationSummaryCard: View {

    let modulation: Modulation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("waveform", modulation.waveform.description)
            row("accent", modulation.accent.description)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(display: name)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 12)
            Text(display: value)
                .font(Typography.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(Palette.text)
        }
    }
}
