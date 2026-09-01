import CoreMIDI
import Engine
import MIDI
import SwiftUI

/// La pantalla del Track.
///
/// **El controlador es el instrumento; la pantalla es el espejo**
/// (`product-guidelines.md`). Nada de lo que hay aquí se edita tocando: el
/// anillo, el playhead y el valor grande informan, y los parámetros
/// generativos se mueven con knobs. Lo táctil se limita a lo que la guía
/// asigna a la pantalla — transporte y selección de dispositivo.
///
/// **Sin controlador conectado la app es de solo lectura y transporte.** El
/// anillo y el playhead siguen viéndose, porque son estado y no edición; lo que
/// no aparece es el valor grande, porque nadie gira nada. No se abre ninguna
/// vía táctil para suplirlo: un slider provisional para Steps o Pulses sería el
/// antipatrón que la guía nombra.
///
/// El panel de medición de jitter sigue debajo porque la Fase 4 del track exige
/// medir con la interfaz corriendo: el anillo redibujándose es justamente la
/// carga visual que faltaba por medir.
struct ContentView: View {

    @State private var model = TransportModel()
    @State private var jitter = JitterMeasurementModel()

    /// Qué familia muestra el panel en reposo.
    ///
    /// **Es navegación, no edición** (FR4): elegir un tab cambia lo que se mira,
    /// nunca lo que suena. Por eso funciona sin controlador conectado — mirar no
    /// es editar — y por eso vive en la vista y no en el modelo.
    @State private var family: ParameterFamily = .shape

    var body: some View {
        // **El ancho se lee una vez, arriba.** La altura del escenario depende
        // del ancho —el anillo es cuadrado y llena su columna— y un
        // `GeometryReader` dentro del `ScrollView` no puede dar las dos cosas
        // sin quedar circular: el `ScrollView` pregunta la altura al contenido y
        // el contenido la sacaría del `ScrollView`.
        GeometryReader { screen in
            content(width: screen.size.width - 64)
        }
    }

    private func content(width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                topBar
                stage(width: width)
                Divider().overlay(Palette.border)
                TrackSelectorView(
                    selected: model.selectedTrackIndex,
                    hasMaterial: model.tracksWithMaterial,
                    channel: model.track.channel,
                    onSelect: { model.selectTrack($0) },
                    onChannelChange: { model.setChannel($0) }
                )
                Divider().overlay(Palette.border)
                TonalView(
                    frame: model.frame,
                    pool: model.track.pool,
                    surface: model.surface,
                    onFrameChange: { model.setFrame($0) }
                )
                Divider().overlay(Palette.border)
                measurement
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background)
        .foregroundStyle(.white)
        .onAppear { jitter.startIfRequestedByLaunchArguments() }
        // **El giro manda sobre el tab.** Mover un knob de otra familia cambia
        // el tab activo en vez de mostrar el valor con un acento que no
        // corresponde al panel: la pantalla es el espejo del controlador, así
        // que sigue a la mano y no al revés.
        .onChange(of: model.transientChange) { _, change in
            if let change { family = change.parameter.family }
        }
    }

    // MARK: - La composición apaisada

    /// **Los anillos a la izquierda, todo lo demás a su derecha** (FR14).
    ///
    /// Sustituye a la columna vertical única con el anillo arriba, que era lo
    /// mínimo para operar de la rebanada 1 y no la pantalla del producto.
    ///
    /// **Es lo que hace posible que el valor grande no tape nunca los anillos**
    /// (FR3). Hoy el valor se dibuja *sobre* el patrón y la guía obliga a que el
    /// patrón permanezca visible bajo él; con dos regiones que no se solapan la
    /// regla se cumple sin excepción, y deja de ser algo que hay que recordar.
    ///
    /// **El anillo pequeño es intencional.** Ocupa un quinto del ancho porque lo
    /// que se lee de un vistazo es la *forma* —cuáles tienen material, cuál está
    /// elegido, por dónde va el tiempo—, no el detalle de un Step. El detalle es
    /// el panel.
    private func stage(width: CGFloat) -> some View {
        let columns = Self.columns(in: width)

        return HStack(alignment: .top, spacing: Self.gutter) {
            rings
                .frame(width: columns.rings, height: columns.rings)

            readout
                .frame(width: columns.readout, height: columns.rings)

            families
                .frame(width: columns.families, height: columns.rings)
        }
    }

    /// El hueco entre columnas.
    static let gutter: CGFloat = 24

    /// El reparto horizontal.
    ///
    /// > **Aquí el handoff se contradice consigo mismo, y gana la app.** El mock
    /// > da al anillo 190 puntos de 924 —un quinto— y el resto a la lectura. Esas
    /// > proporciones se dibujaron para **cinco** anillos; con dieciséis, un
    /// > quinto del ancho deja cada banda en unos 6 puntos y el mapa deja de
    /// > poder contarse. El anillo es lo que la pantalla existe para enseñar
    /// > —`product-guidelines.md`: lo expresivo es el material musical— así que
    /// > se lleva el ancho grande y la lectura se queda con el estrecho.
    /// >
    /// > **Decidido con el usuario el 2026-09-01**, viendo la pantalla:
    /// > «la columna central es demasiado grande; el ancho del anillo debería ser
    /// > el ancho actual de la columna central».
    ///
    /// La lectura y los tabs se calculan primero y **el anillo se queda con lo
    /// que sobra**: así, en un iPad más ancho, el espacio de más va a donde se
    /// nota —más separación entre bandas— y no a estirar un texto que ya cabía.
    static func columns(in total: CGFloat) -> (rings: CGFloat, readout: CGFloat, families: CGFloat)
    {
        let families = min(max(total * (170.0 / 924.0), 170), 260)
        let readout = min(max(total * (190.0 / 924.0), 190), 320)
        let rings = max(total - families - readout - gutter * 2, 240)
        return (rings, readout, families)
    }

    /// La columna izquierda: los dieciséis anillos y nada más.
    private var rings: some View {
        // `TimelineView` redibuja al ritmo de la pantalla, pero **la posición no
        // la decide él**: cada fotograma vuelve a preguntar al modelo, que la
        // resuelve contra el origen que publicó el bucle del scheduler. El
        // movimiento deriva del reloj musical; lo que el temporizador decide es
        // cuándo repintar, no dónde está el tiempo.
        TimelineView(.animation(paused: !model.isPlaying)) { _ in
            RingStackView(
                stack: model.rings,
                selected: model.selectedTrackIndex,
                playheads: model.playheads
            )
        }
        .padding(16)
        .brutalistPanel()
    }

    // MARK: - La barra superior

    /// Lo que el handoff pone arriba: a la izquierda la identidad de lo que
    /// suena, a la derecha el tempo y el transporte (FR6).
    ///
    /// **En el sitio de `Bank 1 · Pattern A` va el estado MIDI.** Banks y
    /// Patterns no existen todavía, y dejar su hueco vacío o rellenarlo con un
    /// nombre inventado serían las dos maneras de mentir. El estado MIDI es lo
    /// que de verdad hay que mirar hoy —de dónde llegan los giros y a dónde
    /// salen las notas— y ocupará otro sitio cuando Banks llegue.
    private var topBar: some View {
        HStack(alignment: .center, spacing: 24) {
            midiStatus
            Spacer(minLength: 24)
            // **El punto decimal no depende del locale.** La interfaz va en
            // inglés y sin traducir (NFR7), y el handoff escribe `120.0 BPM`;
            // interpolar un `Double` daba `120,0` en un iPad en español, que es
            // la mitad del texto en un idioma y la otra mitad en otro.
            Text(
                String(
                    format: "%.1f BPM", locale: Locale(identifier: "en_US_POSIX"),
                    model.beatsPerMinute)
            )
            .font(Typography.bodyMedium)
            .monospacedDigit()
            .foregroundStyle(Palette.mutedBright)
            transport
        }
        .frame(maxWidth: .infinity)
    }

    /// **Estado, nunca disculpa** (`product-guidelines.md`).
    ///
    /// Dice qué hay conectado a cada lado con los textos exactos de la guía. Sin
    /// controlador, `read-only` explica por qué los knobs no hacen nada, que es
    /// información y no una excusa.
    private var midiStatus: some View {
        HStack(spacing: 16) {
            // **A dónde salen las notas.**
            Text(model.outputUnavailable ?? model.destinationStatus)
                .font(Typography.captionStrong)
                .foregroundStyle(model.selection.hasEndpoint ? Palette.shape : Palette.muted)

            // El selector aparece **solo si hay algo que elegir**. Con un único
            // destino, un menú de un elemento sería una decisión que no existe.
            if model.selection.available.count > 1 {
                Picker("Destination", selection: destinationBinding) {
                    ForEach(model.selection.available, id: \.endpoint) { destination in
                        Text(destination.displayName).tag(destination.endpoint)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.mutedBright)
            }

            // **De dónde llegan los giros.**
            Text(model.sourceStatus)
                .font(Typography.captionStrong)
                .foregroundStyle(model.isReadOnly ? Palette.muted : Palette.shape)

            if model.sourceSelection.available.count > 1 {
                Picker("Input", selection: sourceBinding) {
                    ForEach(model.sourceSelection.available, id: \.endpoint) { source in
                        Text(source.displayName).tag(source.endpoint)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.mutedBright)
            }

            // **Sin controlador no se ofrece ninguna vía táctil para suplirlo**:
            // la app es de solo lectura y transporte, y `read-only` explica por
            // qué los knobs no hacen nada. Es información, no una excusa.
            if model.isReadOnly {
                Text("read-only")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .lineLimit(1)
    }

    /// La columna central: la lectura grande.
    ///
    /// En reposo muestra el estado; al girar un knob, el valor transitorio con
    /// el acento de su familia. **Su contenido en reposo lo construye la tarea
    /// siguiente de la Fase 3**; por ahora sostiene lo que ya había.
    private var readout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)

            // **El valor grande sustituye al estado en reposo, no lo tapa**, y
            // sobre todo no tapa los anillos: viven en otra columna (FR14). Con
            // esto la regla de `product-guidelines.md` —el patrón permanece
            // visible bajo el valor— deja de ser algo que haya que recordar al
            // dibujar.
            if let change = model.transientChange {
                transient(change)
            } else {
                resting
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .brutalistPanel()
    }

    /// Lo que el panel dice cuando no se está girando nada.
    ///
    /// El texto lo decide `FamilyReadout`, en `Engine` y con tests. Aquí solo se
    /// compone y se le pone el acento de la familia.
    private var resting: some View {
        let readout = FamilyReadout(track: model.track, family: family)
        return VStack(alignment: .leading, spacing: 8) {
            Text(readout.headline)
                .font(Typography.transientValue)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(Palette.accent(for: family))
            Text(readout.detail)
                .font(Typography.parameterLine)
                .foregroundStyle(Palette.mutedBright)
        }
        .padding(.horizontal, 24)
    }

    /// La columna derecha: los tres tabs de familia.
    ///
    /// **Los construye la tercera tarea de la Fase 3.** Aquí están como las tres
    /// etiquetas que el handoff dibuja, para que la composición se pueda ver y
    /// medir antes de que sean interactivas.
    private var families: some View {
        VStack(spacing: 12) {
            ForEach(ParameterFamily.allCases, id: \.self) { candidate in
                tab(candidate)
            }
            Spacer(minLength: 0)
        }
    }

    /// Un tab de familia, con el tratamiento del handoff: **borde izquierdo
    /// acentuado**, contorno y sombra dura en el activo.
    ///
    /// **Sigue funcionando sin controlador conectado.** La app es de solo
    /// lectura sin knobs, pero mirar no es editar: los tabs cambian qué se mira.
    private func tab(_ candidate: ParameterFamily) -> some View {
        let accent = Palette.accent(for: candidate)
        let isActive = candidate == family

        return Button {
            family = candidate
        } label: {
            HStack(spacing: 12) {
                // El borde izquierdo acentuado: es lo que identifica la familia
                // incluso cuando el tab no está activo.
                Rectangle()
                    .fill(accent)
                    .frame(width: Brutalist.stroke * 2)
                Text(Self.name(of: candidate))
                    .font(isActive ? Typography.captionBold : Typography.captionStrong)
                    .foregroundStyle(isActive ? Palette.toolbar : accent)
                Spacer(minLength: 0)
            }
            // Alto fijo: sin él, el `VStack` reparte entre los tres el alto de
            // la columna y los tabs quedan del tamaño del anillo.
            .frame(height: 64)
            .padding(.trailing, 16)
        }
        .buttonStyle(.plain)
        .brutalistControl(accent: accent, isSelected: isActive)
    }

    /// El vocabulario de la Pre Spec, en inglés y sin traducir (NFR7).
    ///
    /// No sale de `String(describing:)`: el nombre del caso de Swift es un
    /// detalle del lenguaje, y que hoy coincida con el término del dominio no lo
    /// convierte en la fuente de la que copiarlo.
    private static func name(of family: ParameterFamily) -> String {
        switch family {
        case .shape: "SHAPE"
        case .groove: "GROOVE"
        case .tonal: "TONAL"
        }
    }

    // MARK: - El patrón

    /// El valor grande.
    ///
    /// Tipografía muy grande y jerarquía marcada porque el criterio es leerlo a
    /// Displays the description of a parameter change with its family-specific accent color.
    /// - Parameter change: The parameter change to display.
    /// - Returns: A view showing the change description.
    private func transient(_ change: ParameterChange) -> some View {
        Text(change.description)
            .font(Typography.transientValue)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            // **El acento es el de la familia del parámetro que se movió**, no
            // uno fijo: `product-guidelines.md` pide que el color codifique qué
            // tipo de parámetro es. Girar Velocity y girar Steps tienen que
            // leerse distinto sin necesidad de leer la palabra.
            .foregroundStyle(Palette.accent(for: change.parameter.family))
            .padding(.horizontal, 24)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: change)
    }

    // MARK: - Transporte

    /// Si el botón de transporte hace algo ahora mismo.
    ///
    /// Se puede parar siempre que esté sonando, y arrancar solo si hay destino.
    private var canTransport: Bool { model.canPlay || model.isPlaying }

    /// **Sin el nombre de la app.** Estaba desde la rebanada 1 y no lo pide
    /// ningún requisito: el handoff no lo dibuja en ninguna de sus cinco
    /// pantallas, y `product-guidelines.md` dice que la app informa —el usuario
    /// ya sabe qué app abrió—. Quitado el 2026-09-01, a petición del usuario.
    private var transport: some View {
        // **Era `.borderedProminent`, que dibuja una pastilla completa**, y FR9
        // lo prohíbe: el radio pequeño y constante es lo que hace que la
        // pantalla se lea como un aparato y no como un formulario. Es primario,
        // así que lleva relleno de acento y sombra dura siempre que se pueda
        // pulsar.
        Button(model.isPlaying ? "Stop" : "Play") {
            model.isPlaying ? model.stop() : model.play()
        }
        .font(Typography.transportLabel)
        .buttonStyle(.plain)
        .foregroundStyle(canTransport ? Palette.toolbar : Palette.muted)
        .disabled(!canTransport)
        // Objetivo táctil holgado: se toca de pie, delante del sintetizador.
        .frame(minWidth: 160, minHeight: 60)
        .brutalistControl(
            accent: Palette.shape,
            isSelected: canTransport,
            radius: Brutalist.radiusLarge
        )
    }

    private var sourceBinding: Binding<MIDIEndpointRef> {
        Binding(
            get: { model.sourceSelection.selected?.endpoint ?? 0 },
            set: { endpoint in
                guard
                    let chosen = model.sourceSelection.available.first(where: {
                        $0.endpoint == endpoint
                    })
                else { return }
                model.selectSource(chosen)
            }
        )
    }

    private var destinationBinding: Binding<MIDIEndpointRef> {
        Binding(
            get: { model.selection.selected?.endpoint ?? 0 },
            set: { endpoint in
                guard
                    let chosen = model.selection.available.first(where: { $0.endpoint == endpoint })
                else { return }
                model.select(chosen)
            }
        )
    }

    /// Los valores de Shape y de Groove, en solo lectura.
    ///
    /// **Cada familia con su acento**, para que el estado en reposo se lea con
    /// el mismo código de color que el valor grande transitorio.
    ///
    /// No se muestra ninguna altura: el pool tiene su propia representación en
    /// `TonalView`, y enseñar una nota por paso contradiría el modelo de pool de
    /// la Pre Spec.
    private var parameters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.shapeSummary)
                .font(Typography.parameterLine)
                .foregroundStyle(Palette.shape.opacity(0.85))
            // Dos renglones, un solo acento: el color codifica la familia y
            // Groove es una. El corte lo decide `Engine` —por lo que se envía y
            // por cuándo se envía— y no el ancho de la pantalla, que dejaba
            // `Delay 0%` colgando solo.
            ForEach(model.grooveSummaryLines, id: \.self) { line in
                Text(line)
                    .font(Typography.parameterLine)
                    .foregroundStyle(Palette.groove.opacity(0.85))
            }
        }
    }

    // MARK: - Medición de jitter

    private var measurement: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jitter")
                .font(Typography.sectionTitle)
            Text(jitter.statusMessage)
                .font(Typography.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            HStack(spacing: 20) {
                Button(jitter.isRunning ? "Detener" : "Medir") {
                    jitter.isRunning ? jitter.stop() : jitter.start()
                }
                .buttonStyle(.bordered)

                Picker("Eventos por tempo", selection: $jitter.sampleCount) {
                    ForEach(JitterMeasurementModel.sampleCountOptions, id: \.self) { count in
                        Text("\(count) eventos").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(jitter.isRunning)
                .frame(maxWidth: 320)
            }

            // La rejilla con la que medir. La recta es la de siempre, y es la
            // que se compara contra la referencia; las otras tres son las que la
            // rebanada 6 tiene que demostrar.
            Picker("Rejilla", selection: $jitter.grid) {
                ForEach(JitterMeasurementModel.Grid.allCases) { grid in
                    Text(grid.rawValue).tag(grid)
                }
            }
            .pickerStyle(.segmented)
            .disabled(jitter.isRunning)
            .frame(maxWidth: 520)

            Text("Umbral: máx < 2 ms · σ < 0,5 ms")
                .font(Typography.caption)
                .foregroundStyle(.secondary)

            if let failure = jitter.failureMessage {
                Text(failure)
                    .font(Typography.body)
                    .foregroundStyle(.orange)
            }

            ForEach(jitter.measurements, id: \.beatsPerMinute) { measurement in
                row(for: measurement)
            }

            if let verdict = jitter.overallVerdict {
                Text(verdict ? "VEREDICTO: CUMPLE" : "VEREDICTO: NO CUMPLE")
                    .font(Typography.valueTitle)
                    .foregroundStyle(verdict ? .green : .red)
            }
        }
    }

    private func row(for measurement: JitterMeasurement) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("\(Int(measurement.beatsPerMinute)) BPM")
                .font(Typography.bodyMedium).monospacedDigit()
                .frame(width: 90, alignment: .leading)

            Text(measurement.statistics.summary)
                .font(Typography.reading)
                .foregroundStyle(measurement.statistics.meetsTrackThreshold ? .green : .red)
        }
    }
}

#Preview {
    ContentView()
}
