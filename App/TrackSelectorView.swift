import Engine
import SwiftUI

/// Los dieciséis Tracks: cuál se edita y cuáles tienen material.
///
/// **No es la pantalla del handoff.** Los anillos concéntricos —uno por Track—
/// son la rebanada siguiente; esto es lo justo para que dieciséis Tracks se
/// puedan usar y verificar sin adivinar cuál está seleccionado.
///
/// **Seleccionar desde aquí hace lo mismo que su step button.** Sin controlador
/// conectado es la única vía, y con controlador las dos llevan al mismo sitio:
/// si no, la pantalla mentiría sobre lo que el hardware acaba de hacer.
struct TrackSelectorView: View {

    let selected: Int
    /// Cuáles tienen material. Un Track vacío dispara y no suena, así que la
    /// diferencia importa antes de preguntarse por qué no se oye.
    let hasMaterial: [Bool]
    /// Por dónde emite cada uno. Va en la pastilla (FR5).
    let channels: [Channel]
    /// El acento de la familia activa, que es el que lleva el elegido (FR5).
    let accent: Color
    let onSelect: (Int) -> Void
    let onChannelChange: (Channel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selector
            channelRow
        }
    }

    // MARK: - Los dieciséis

    /// **Una fila de dieciséis** (FR5), no dos de ocho.
    ///
    /// Dos filas se leían como dos grupos y los Tracks no están agrupados: el 8
    /// y el 9 son tan contiguos como el 3 y el 4. En una fila el orden es el
    /// mismo que el de los step buttons del controlador, que es la superficie
    /// desde la que se seleccionan de verdad.
    private var selector: some View {
        HStack(spacing: 6) {
            ForEach(0..<16, id: \.self) { index in
                button(for: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Una pastilla: **su número y su canal**.
    ///
    /// Tres estados que se leen sin texto: el elegido va relleno del acento de
    /// la familia activa, los que tienen material llevan ese acento en el trazo,
    /// y los vacíos solo el borde en reposo.
    private func button(for index: Int) -> some View {
        let isSelected = index == selected
        let sounds = hasMaterial.indices.contains(index) && hasMaterial[index]
        let channel = channels.indices.contains(index) ? channels[index] : .first

        return Button {
            onSelect(index)
        } label: {
            VStack(spacing: 2) {
                Text("\(index + 1)")
                    .font(isSelected ? Typography.bodyStrong : Typography.body)
                    .foregroundStyle(
                        isSelected ? Palette.toolbar : (sounds ? accent : Palette.muted))
                // El canal en pequeño y debajo: es de qué instrumento sale, no
                // qué Track es. Si compartieran tamaño habría que leer cuál es
                // cuál.
                Text("\(channel.number)")
                    .font(Typography.caption)
                    .foregroundStyle(isSelected ? Palette.toolbar.opacity(0.7) : Palette.muted)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.plain)
        .brutalistControl(
            accent: accent,
            isSelected: isSelected,
            isPopulated: sounds,
            radius: Brutalist.radius
        )
    }

    // MARK: - El canal

    /// Por dónde sale este Track.
    ///
    /// **Táctil, como Scale y Root**: es configuración y no material generativo,
    /// y `product-guidelines.md` pone esa frontera del lado de la pantalla.
    /// El canal del Track elegido, que es el que esta fila edita.
    private var selectedChannel: Channel {
        channels.indices.contains(selected) ? channels[selected] : .first
    }

    private var channelRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Channel · Track \(selected + 1)")
            HStack(spacing: 6) {
                ForEach(1...16, id: \.self) { number in
                    let isSelected = number == selectedChannel.number
                    Button("\(number)") { onChannelChange(Channel(number)!) }
                        .font(isSelected ? Typography.captionBold : Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Palette.toolbar : Palette.muted)
                        .frame(minWidth: 34, minHeight: 44)
                        .brutalistControl(
                            accent: accent,
                            isSelected: isSelected,
                            radius: Brutalist.radiusSmall
                        )
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Typography.captionStrong)
            .foregroundStyle(Palette.muted)
    }
}
