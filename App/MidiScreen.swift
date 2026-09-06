import CoreMIDI
import Engine
import MIDI
import SwiftUI

/// La pantalla `midi`: de dónde viene el pulso, por dónde entra el control y por
/// dónde salen las notas.
///
/// **Es configuración, no interpretación.** Se visita entre tema y tema, no se
/// mira mientras se toca — por eso el estado que sí hay que ver de reojo (el
/// punto de conexión, el tempo, quién manda el reloj) vive arriba en la barra y
/// aquí está lo que se decide una vez.
struct MidiScreen: View {

    let model: TransportModel

    var body: some View {
        // El tempo y el estado del maestro los escribe el hilo de recepción de
        // CoreMIDI, que no publica nada observable: hay que repreguntar.
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    ClockSourceCard(model: model)
                    MidiInputCard(model: model)
                    MidiOutputCard(model: model)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TrackChannels(
                    channels: model.channels,
                    selected: model.selectedTrackIndex,
                    onChange: { model.setChannel($1, forTrack: $0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// De dónde sale el pulso.
///
/// **Sin control de tempo** (FR21). El handoff no lo dibuja aquí y el ajuste vive
/// en la barra, colgado del número: repetirlo daría dos sitios donde cambiar lo
/// mismo, y el que se quedara atrás mentiría.
struct ClockSourceCard: View {

    let model: TransportModel

    var body: some View {
        Card(title: "clock source") {
            // **Un segmentado propio y no el de UIKit.** El de sistema llega con
            // su cápsula, su relleno degradado y su animación deslizante — tres
            // cosas que FR2 deja fuera. Dos botones con el mismo lenguaje que el
            // resto dicen lo mismo.
            HStack(spacing: 0) {
                // **Los dos casos de `ClockSource`, no dos literales.** Los
                // nombres los pone `MIDI`; recorrer el tipo además garantiza que
                // una tercera fuente, si alguna vez la hay, aparezca aquí sola
                // en vez de faltar en silencio.
                segment(.internal)
                segment(.external)
            }
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: Brutalist.radius))
            .overlay {
                RoundedRectangle(cornerRadius: Brutalist.radius)
                    .stroke(Palette.border, lineWidth: Brutalist.stroke)
            }

            // **Lo que el reloj está haciendo, no lo que se eligió.** Con reloj
            // externo el texto lo escribe `clockStatus`, que distingue seguir a
            // un maestro de haberlo perdido; sin él, no hay nada que contar y se
            // dice el tempo.
            Text(display: status)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    private var status: String {
        if let external = model.clockStatus { return external }
        return "internal clock · \(model.tempoDescription)"
    }

    private func segment(_ source: ClockSource) -> some View {
        let isExternal = source == .external
        let isSelected = model.followsExternalClock == isExternal

        return Button(action: { model.setFollowsExternalClock(isExternal) }) {
            Text(display: source.name)
                .font(isSelected ? Typography.bodyStrong : Typography.body)
                .foregroundStyle(isSelected ? Palette.onAccent : Palette.mutedBright)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Palette.offWhite : .clear,
            in: RoundedRectangle(cornerRadius: Brutalist.radius)
        )
    }
}

/// Por dónde entran los giros.
struct MidiInputCard: View {

    let model: TransportModel

    var body: some View {
        Card(title: "midi input") {
            if model.sourceSelection.available.isEmpty {
                // **Nada conectado no es «no disponible».** El borde discontinuo
                // significa «existe y todavía no se puede usar»; aquí no existe
                // ninguna entrada, y decirlo con ese signo prometería un
                // dispositivo que no está.
                Text(display: model.sourceStatus)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, 12)
            } else {
                ForEach(model.sourceSelection.available, id: \.endpoint) { endpoint in
                    EndpointRow(
                        name: endpoint.displayName,
                        isSelected: model.sourceSelection.selected == endpoint,
                        onSelect: { model.selectSource(endpoint) }
                    )
                }
            }
        }
    }
}

/// Por dónde salen las notas.
struct MidiOutputCard: View {

    let model: TransportModel

    var body: some View {
        Card(title: "midi output") {
            if let unavailable = model.outputUnavailable {
                // **Aquí sí toca el borde discontinuo.** La salida existe como
                // función y no se puede usar porque CoreMIDI no la dejó crear:
                // es exactamente «existe y todavía no se puede usar».
                Text(display: unavailable)
                    .font(Typography.bodyMedium)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .brutalistUnavailable()
            } else if model.selection.available.isEmpty {
                Text(display: model.destinationStatus)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, 12)
            } else {
                ForEach(model.selection.available, id: \.endpoint) { endpoint in
                    EndpointRow(
                        name: endpoint.displayName,
                        isSelected: model.selection.selected == endpoint,
                        onSelect: { model.select(endpoint) }
                    )
                }

                Text(display: "channel routing active")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
    }
}

/// Una fila de dispositivo: su nombre, y si es el elegido.
struct EndpointRow: View {

    let name: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text(display: name)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(isSelected ? Palette.text : Palette.mutedBright)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if isSelected {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Palette.shape)
                            .frame(width: 8, height: 8)
                        Text(display: "connected")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.mutedBright)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Brutalist.radius))
        .overlay {
            RoundedRectangle(cornerRadius: Brutalist.radius)
                .stroke(
                    isSelected ? Palette.shape : Palette.border,
                    lineWidth: isSelected ? Brutalist.strokeEmphasis : Brutalist.stroke
                )
        }
    }
}

/// Por qué canal emite cada Track.
///
/// **Los doce a la vez** (FR24). Es lo que permite ver dos Tracks compartiendo
/// canal sin ir seleccionándolos uno a uno, que es el problema que esta pantalla
/// existe para resolver.
struct TrackChannels: View {

    let channels: [Channel]
    let selected: Int
    let onChange: (Int, Channel) -> Void

    /// Qué fila tiene abierto su selector de canal, si hay alguna.
    @State private var editing: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display: "track channels")
                .font(Typography.parameterLine)
                .foregroundStyle(Palette.muted)

            ForEach(0..<Pattern.trackCount, id: \.self) { index in
                row(index)
            }

            Text(display: "\(Pattern.trackCount) tracks routed")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    private func row(_ index: Int) -> some View {
        let channel = channels.indices.contains(index) ? channels[index] : .first
        let isSelected = index == selected
        let isEditing = editing == index

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                cell(
                    "track \((index + 1).paddedForDisplay)",
                    isEmphasised: isSelected,
                    alignment: .leading
                )

                Button {
                    // **El selector se despliega en línea, no en un menú.** Un
                    // `Menu` de SwiftUI llega con la cápsula y la sombra
                    // difuminada del sistema, que FR2 deja fuera; es la misma
                    // razón por la que el ajuste de tempo dejó de ser un popover
                    // en la Fase 1.
                    editing = isEditing ? nil : index
                } label: {
                    cell(
                        "ch \(channel.number.paddedForDisplay)",
                        isEmphasised: isSelected,
                        alignment: .leading
                    )
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                // Los dieciséis canales, para elegir sin contar clics.
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
                    spacing: 4
                ) {
                    ForEach(Channel.validRange, id: \.self) { number in
                        let candidate = Channel(number)!

                        Button(number.paddedForDisplay) {
                            onChange(index, candidate)
                            editing = nil
                        }
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(
                            candidate == channel ? Palette.onAccent : Palette.mutedBright
                        )
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                        .brutalistControl(
                            accent: Palette.offWhite,
                            isSelected: candidate == channel,
                            radius: Brutalist.radiusSmall
                        )
                    }
                }
            }
        }
    }

    private func cell(
        _ text: String, isEmphasised: Bool, alignment: Alignment
    ) -> some View {
        Text(display: text)
            .font(isEmphasised ? Typography.bodyStrong : Typography.body)
            .monospacedDigit()
            .foregroundStyle(isEmphasised ? Palette.text : Palette.mutedBright)
            .padding(.horizontal, 12)
            // **40 y no 44.** Doce filas más su cabecera y su pie llenan la
            // columna justo hasta el borde, y el selector de canal se despliega
            // dentro de ella: sin este margen, abrir una fila empuja el pie
            // fuera de la pantalla en vez de caber.
            .frame(maxWidth: .infinity, minHeight: 40, alignment: alignment)
            .contentShape(Rectangle())
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: Brutalist.radius))
            .overlay {
                RoundedRectangle(cornerRadius: Brutalist.radius)
                    .stroke(
                        isEmphasised ? Palette.offWhite : Palette.border,
                        lineWidth: isEmphasised ? Brutalist.strokeEmphasis : Brutalist.stroke
                    )
            }
    }
}

/// Un card de esta pantalla: título arriba y contenido debajo, con el trazo del
/// sistema.
///
/// Existe para que los tres de la izquierda no repitan el mismo envoltorio tres
/// veces, que es como empiezan a divergir.
struct Card<Content: View>: View {

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display: title)
                .font(Typography.parameterLine)
                .foregroundStyle(Palette.muted)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }
}
