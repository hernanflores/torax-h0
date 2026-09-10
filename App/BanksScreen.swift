import Engine
import Persistence
import SwiftUI

/// La pantalla `banks`: bancos, patterns y a qué pattern responde cada Track.
///
/// **Dejó de ser cáscara el 2026-09-07**, y la forma no cambió — que es lo que
/// su versión anterior prometió: «el día que exista el modelo de `Bank` esta
/// pantalla deja de ser cáscara **sin cambiar de forma**». Los tres cards siguen
/// donde estaban.
///
/// Lo que cambia es que detrás hay algo: dieciséis Banks de dieciséis Patterns
/// que existen, se eligen y se guardan.
///
/// **El cuarto estado es `queued`**, con la cuenta atrás en negras. Entre pulsar
/// un Pattern y el compás en que entra pasa hasta un compás —cuatro segundos a
/// 60 BPM— y sin decirlo la espera se lee como que el botón no funciona.
///
/// **Y aquí se toca mientras suena.** Es la enmienda del 2026-09-07 a la
/// frontera del tacto: `banks` estaba del lado de «se configura antes de tocar»,
/// y elegir un Pattern es un gesto de directo. La frontera real no era temporal
/// sino qué se edita con el dedo, y aquí no se edita material generativo: se
/// elige cuál suena.
struct BanksScreen: View {

    let model: TransportModel

    var body: some View {
        // **Alineados arriba y sin estirar.** Con los cards ocupando toda la
        // altura, el pie del banco quedaba pegado al borde inferior y se
        // recortaba; cada uno mide ahora lo que mide su contenido.
        HStack(alignment: .top, spacing: 20) {
            BankGrid(
                selected: model.selectedBankIndex,
                tempo: model.tempoDescription,
                patternsWithMaterial: model.bank.patternsWithMaterial,
                onSelect: model.selectBank
            )

            PatternGrid(
                selected: model.selectedPatternIndex,
                states: model.patternSlotStates,
                beatsUntilChange: model.beatsUntilPatternChange,
                copied: model.copiedSlotIndex,
                pasteDestination: model.pasteDestinationIndex,
                onSelect: model.selectPattern,
                canPaste: model.canPaste,
                isRunning: model.isPlaying,
                onCopy: model.copyPattern,
                onPaste: model.pastePattern,
                onChordCopy: model.copyPattern(from:to:),
                onClear: model.clearPattern
            )

            VStack(alignment: .leading, spacing: 20) {
                SaveControls(
                    reload: model.reloadAvailability,
                    onSave: model.saveBank,
                    onReload: model.reloadBank
                )
                TrackAssignments(
                    selected: model.selectedTrackIndex,
                    pattern: model.selectedPatternIndex
                )
            }
        }
    }
}

/// Los dieciséis bancos.
struct BankGrid: View {

    let selected: Int
    let tempo: String
    let patternsWithMaterial: Int
    let onSelect: (Int) -> Void

    /// **La constante se fue con `Bank`, el 2026-09-07.** Vivía aquí porque
    /// bajarla habría exigido inventar un tipo que no existía; ahora existe, y
    /// `Project.bankCount` es su sitio.

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display: "bank \((selected + 1).paddedForDisplay)")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<Project.bankCount, id: \.self) { index in
                    let isSelected = index == selected

                    Button((index + 1).paddedForDisplay) { onSelect(index) }
                        .font(isSelected ? Typography.bodyStrong : Typography.body)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Palette.onAccent : Palette.mutedBright)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                        // Off-white: elegir un banco es «éste entre iguales», no
                        // pertenece a ninguna familia de parámetros.
                        .brutalistControl(accent: Palette.offWhite, isSelected: isSelected)
                }
            }

            // **Cuenta los que tienen material, no los huecos.** El handoff
            // rotula «16 patterns», que es la capacidad; decir eso con quince
            // vacíos sería contar sitios y llamarlos contenido.
            Text(display: "\(tempo) · \(patterns)")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    /// **No reusa `PitchPool.countDescription` aunque tenga la misma forma.**
    /// Aquella se movió a `Engine` porque el *mismo* concepto se escribía en
    /// tres sitios con tres redacciones distintas; ésta cuenta otra cosa y se
    /// escribe una vez. Compartirlas pediría una plantilla genérica de
    /// singular y plural, que es más maquinaria que la que ahorra.
    private var patterns: String {
        switch patternsWithMaterial {
        case 0: "no patterns"
        case 1: "1 pattern"
        default: "\(patternsWithMaterial) patterns"
        }
    }
}

/// Los dieciséis patterns del banco, con su estado.
struct PatternGrid: View {

    let selected: Int

    /// Los dieciséis estados, calculados en `Engine`.
    ///
    /// **La vista no clasifica.** La regla —quién manda cuando un hueco suena y
    /// además espera, y que parado no hay espera— vive en `PatternSlotState`,
    /// donde hay tests.
    let states: [PatternSlotState]

    /// Cuántas negras faltan para que entre el Pattern armado.
    let beatsUntilChange: Int?

    /// El hueco del que salió lo que hay en el portapapeles, si está en este
    /// Bank (FR12).
    let copied: Int?

    /// Dónde caería un pegado ahora, para saber qué celda destella.
    let pasteDestination: Int?

    let onSelect: (Int) -> Void

    /// Si hay algo en el portapapeles. Vacío, `paste` no se puede pulsar (FR4).
    let canPaste: Bool

    /// Si el transporte corre. **El acorde solo actúa corriendo** (FR15).
    let isRunning: Bool

    let onCopy: () -> Void
    let onPaste: () -> Void
    let onChordCopy: (Int, Int) -> Void
    let onClear: (Int) -> Void

    /// Dónde quedó dibujada cada celda. Lo dicen las celdas y lo lee la capa de
    /// toques.
    @State private var cellFrames: [CGRect] = []

    /// Los huecos con un dedo encima ahora mismo.
    ///
    /// **El resaltado de pulsación se conserva a mano**, porque es lo que un
    /// `Button` daba gratis y su ausencia se leería como que la rejilla no
    /// responde.
    @State private var pressed: Set<Int> = []

    /// La regla del acorde, que decide qué significa cada toque cuando el
    /// transporte corre. Vive en `Engine`, donde hay tests.
    @State private var chord = PatternChord()

    /// La celda que está destellando ahora mismo, si alguna.
    @State private var flashed: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(display: "patterns")
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.text)

                Spacer()

                // **La cuenta atrás solo aparece cuando hay algo esperando.**
                // Un contador siempre visible sería ruido en la pantalla que más
                // se mira de reojo.
                if let beatsUntilChange {
                    Text(display: "in \(beatsUntilChange)")
                        .font(Typography.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(Palette.shape)
                }
            }

            // **La rejilla resuelve sus propios toques** desde el 2026-09-10.
            // Dos `Button` hermanos de SwiftUI no ven toques simultáneos, así
            // que el acorde de dos dedos no se podía expresar con dieciséis
            // botones. Las celdas se dibujan y una capa encima traduce los
            // toques a índices; lo que significan lo decide `PatternChord`.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<Bank.patternCount, id: \.self) { index in
                    cell(index)
                }
            }
            .coordinateSpace(name: Self.gridSpace)
            .onPreferenceChange(PatternCellFrames.self) { frames in
                cellFrames = (0..<Bank.patternCount).map { frames[$0] ?? .zero }
            }
            .overlay {
                PatternTouchLayer(
                    cellFrames: cellFrames,
                    onDown: down,
                    onUp: up,
                    onCancel: cancel
                )
            }

            // **Los tres operan sobre el hueco elegido**, y por eso están
            // debajo de la rejilla y no dentro de cada celda: dieciséis tríos de
            // botones diminutos serían imposibles de acertar con el dedo.
            //
            // **`copy here` era un gesto de un solo paso que nunca existió**: la
            // pantalla conoce un índice y se lo pasaba a las dos puntas de la
            // copia, así que la celda se copiaba sobre sí misma. Dos gestos y un
            // portapapeles sí se pueden expresar — y el portapapeles guarda el
            // Pattern entero, así que se puede pegar en otro Bank.
            HStack(spacing: 8) {
                Button("copy") { onCopy() }
                    .brutalistControl(accent: Palette.offWhite, isSelected: false)
                Button("paste") { paste() }
                    .brutalistControl(accent: Palette.offWhite, isSelected: false)
                    .disabled(!canPaste)
                Button("clear") { onClear(selected) }
                    .brutalistControl(accent: Palette.offWhite, isSelected: false)
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.mutedBright)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    private func state(_ index: Int) -> PatternSlotState {
        index < states.count ? states[index] : .empty
    }

    /// El espacio en el que se miden las celdas y en el que la capa de toques
    /// las busca. Los dos tienen que hablar del mismo origen.
    private static let gridSpace = "patternGrid"

    /// Un dedo baja sobre una celda.
    ///
    /// **Corriendo, el segundo dedo copia en el acto**, que es lo que hace que
    /// el acorde responda ya y que el orden de levantada dé igual.
    ///
    /// **Parado no hay acorde** (FR15): el toque sencillo carga el Pattern de
    /// inmediato, así que el `down` del primer dedo ya habría cambiado el
    /// material antes de saber si el toque era un acorde. Ahí solo se resalta.
    private func down(_ index: Int) {
        pressed.insert(index)
        guard isRunning else { return }
        apply(chord.pressing(index))
    }

    /// Un dedo se levanta sobre su celda: selecciona, que es donde un `Button`
    /// ya lo resolvía (FR20).
    ///
    /// Corriendo, la regla decide: si el toque fue parte de un acorde, no
    /// selecciona nada y **sigue sonando lo que sonaba** (FR17, FR18).
    private func up(_ index: Int) {
        pressed.remove(index)

        guard isRunning else {
            onSelect(index)
            return
        }
        apply(chord.releasing(index))
    }

    /// Un toque que se levanta fuera de su celda no selecciona (FR21).
    private func cancel(_ index: Int) {
        pressed.remove(index)
        guard isRunning else { return }
        apply(chord.cancelling(index))
    }

    /// Hace lo que la regla decidió.
    ///
    /// **El acorde no arma, no mueve la selección, no toca el transporte ni
    /// `pendingAdoption`** (FR18): copiar escribe material y nada más. Y carga
    /// el portapapeles con el origen (FR19), así que el backup hecho con dos
    /// dedos se puede llevar luego a otro Bank con `paste`.
    private func apply(_ effect: PatternChord.Effect) {
        switch effect {
        case .none:
            break
        case .select(let index):
            onSelect(index)
        case .copy(let origin, let destination):
            onChordCopy(origin, destination)
            flash(destination)
        }
    }

    /// Pega, y **destella la celda que recibió el material** (FR13).
    ///
    /// El destino se pide antes de pegar: pegar puede cambiar lo que la vista
    /// sabe, y la celda que destella es la que recibió, no la que reciba la
    /// próxima vez.
    private func paste() {
        let destination = pasteDestination
        onPaste()
        if let destination { flash(destination) }
    }

    /// El destello de la celda de destino (FR13, FR14).
    ///
    /// **Se enciende y se apaga solo, sin colgarse del reloj**: no es una
    /// animación al ritmo del transporte sino un desvanecido de una vez, así que
    /// no añade trabajo por cuadro ni depende de que algo esté sonando.
    ///
    /// El salto a la siguiente vuelta del bucle es lo que separa el encendido
    /// del apagado; en la misma pasada SwiftUI los fundiría en uno y no se vería
    /// nada.
    private func flash(_ index: Int) {
        flashed = index
        Task { @MainActor in
            withAnimation(.easeOut(duration: Brutalist.flashDuration)) { flashed = nil }
        }
    }

    private func cell(_ index: Int) -> some View {
        let state = state(index)
        let isSelected = index == selected

        return VStack(spacing: 4) {
            Text(display: (index + 1).paddedForDisplay)
                .font(state == .playing ? Typography.valueTitle : Typography.parameterLine)
                .monospacedDigit()
                .foregroundStyle(state == .playing ? Palette.shape : Palette.mutedBright)

            Text(display: state.label)
                .font(Typography.caption)
                .foregroundStyle(state == .empty ? Palette.border : Palette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .contentShape(Rectangle())
        .opacity(pressed.contains(index) ? Brutalist.pressedOpacity : 1)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Brutalist.radius))
        .overlay {
            RoundedRectangle(cornerRadius: Brutalist.radius)
                .stroke(border(state: state, isSelected: isSelected), lineWidth: width(isSelected))
        }
        // **La marca de origen es un bloque en la esquina**, no un borde: los
        // tres bordes ya están repartidos entre el que suena, el que espera y el
        // elegido, y un cuarto no se distinguiría a un metro (FR12).
        .overlay(alignment: .topTrailing) {
            if index == copied {
                Rectangle()
                    .fill(Palette.offWhite)
                    .frame(width: Brutalist.copyMark, height: Brutalist.copyMark)
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Brutalist.radius)
                .fill(Palette.offWhite)
                .opacity(index == flashed ? 1 : 0)
                .allowsHitTesting(false)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PatternCellFrames.self,
                    value: [index: proxy.frame(in: .named(Self.gridSpace))]
                )
            }
        }
        // **La celda deja de ser un `Button` pero no deja de ser pulsable.**
        // VoiceOver la sigue leyendo como tal y la sigue pudiendo activar; el
        // acorde es un gesto de dos dedos que no tiene equivalente accesible, y
        // para eso están `copy` y `paste`.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            index == copied
                ? "pattern \(index + 1), \(state.label), copied"
                : "pattern \(index + 1), \(state.label)"
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect(index) }
    }

    /// **El que suena lleva el olivo de Shape; el que espera, el mismo olivo más
    /// fino; el elegido, el off-white.** Son tres cosas distintas y coinciden a
    /// menudo: separarlas es lo que permite mirar un pattern sin dejar de ver
    /// cuál suena ni cuál va a entrar.
    private func border(state: PatternSlotState, isSelected: Bool) -> Color {
        if state == .playing { return Palette.shape }
        if state == .queued { return Palette.shape }
        if isSelected { return Palette.offWhite }
        return state == .empty ? Palette.border : Palette.borderBright
    }

    private func width(_ isSelected: Bool) -> CGFloat {
        isSelected ? Brutalist.strokeEmphasis : Brutalist.stroke
    }
}

/// `Save Bank` y `Reload`.
///
/// **`Reload` deshabilitado lleva su motivo debajo** (FR17). Un botón apagado sin
/// explicación se lee como un fallo de la app; aquí es información sobre cómo
/// funciona el guardado.
///
/// **Sin modales**, que `workflow.md` prohíbe mientras el transporte corre.
struct SaveControls: View {

    let reload: ReloadAvailability
    let onSave: () -> Void
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display: "bank")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)

            HStack(spacing: 8) {
                Button("save bank", action: onSave)
                    .brutalistControl(accent: Palette.offWhite, isSelected: false)
                    .foregroundStyle(Palette.mutedBright)

                Button("reload", action: onReload)
                    .brutalistControl(accent: Palette.offWhite, isSelected: false)
                    .foregroundStyle(reload.isAvailable ? Palette.mutedBright : Palette.border)
                    .disabled(!reload.isAvailable)
            }
            .font(Typography.caption)

            if let reason = reload.reason {
                Text(display: reason)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }
}

/// A qué pattern responde cada Track.
///
/// **Los doce dicen el mismo pattern, y es la verdad.** Con un solo `Pattern`,
/// los doce Tracks son suyos: no hay asignación que enseñar todavía. Inventar
/// doce asignaciones distintas para que se parezca al mock sería exactamente lo
/// que FR25 dice que esta pantalla no hace.
struct TrackAssignments: View {

    let selected: Int

    /// Qué Pattern está sonando. **Los doce dicen el mismo y sigue siendo la
    /// verdad**: un Pattern son sus doce Tracks, no doce asignaciones
    /// independientes. Lo que cambia respecto a la cáscara es que ya no dice
    /// siempre `01`.
    let pattern: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display: "track assignments")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.text)

            // **Las doce filas van pegadas, con su propio espaciado.** Con el
            // del card —doce puntos entre bloques— las doce sumaban más de lo
            // que la columna tiene y `track 12` caía fuera de la pantalla.
            VStack(spacing: 4) {
                ForEach(0..<Pattern.trackCount, id: \.self) { index in
                    row(index)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    private func row(_ index: Int) -> some View {
        let isSelected = index == selected

        return HStack(spacing: 0) {
            Text(display: "track \((index + 1).paddedForDisplay)")
                .font(isSelected ? Typography.bodyStrong : Typography.body)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Palette.shape : Palette.mutedBright)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(display: "pattern \((pattern + 1).paddedForDisplay)")
                .font(isSelected ? Typography.bodyStrong : Typography.body)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Palette.shape : Palette.mutedBright)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: Brutalist.radiusSmall))
        .overlay {
            RoundedRectangle(cornerRadius: Brutalist.radiusSmall)
                .stroke(
                    isSelected ? Palette.shape : Palette.border,
                    lineWidth: isSelected ? Brutalist.strokeEmphasis : Brutalist.stroke
                )
        }
    }
}
