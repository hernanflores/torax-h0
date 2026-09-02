import Engine
import SwiftUI

/// Por dónde emite cada Track: el ruteo MIDI completo, en una pantalla.
///
/// **El canal es configuración, no material generativo.** La frontera de
/// `product-guidelines.md` pone la configuración del lado de la pantalla, junto
/// a Scale, Root y la selección de dispositivo — y su sitio es la pantalla MIDI,
/// no la de Track: dice de qué instrumento sale un Track, no qué toca.
///
/// **Los doce a la vez, y no el seleccionado.** Es la razón de que esta vista
/// exista en lugar de mover la fila anterior de sitio: dos Tracks compartiendo
/// canal es un caso real —dos capas rítmicas sobre el mismo sinte— y también un
/// error frecuente, y ninguna de las dos cosas se ve si hay que ir Track por
/// Track. Aquí se leen las doce filas de una vez.
///
/// **Cambiar un canal no cambia el Track seleccionado.** Elegir instrumento y
/// elegir a quién escuchan los knobs son dos cosas distintas; mezclarlas movería
/// la edición al ajustar el ruteo.
struct ChannelMapView: View {

    /// El canal de cada Track, por posición.
    let channels: [Channel]
    /// Cuál se está editando en la pantalla Track.
    ///
    /// **Solo se marca, no se cambia desde aquí.** Sirve para reencontrarse: al
    /// venir de la pantalla Track, saber cuál se estaba tocando ahorra contar
    /// filas.
    let selected: Int
    /// El acento de la familia activa, el mismo que lleva el resto de la app.
    let accent: Color
    let onChannelChange: (Int, Channel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            VStack(spacing: 8) {
                ForEach(0..<Pattern.trackCount, id: \.self) { index in
                    row(for: index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Channel")
                .font(Typography.captionStrong)
                .foregroundStyle(Palette.muted)
            // **Estado, no explicación.** La guía de voz pide informar y no
            // acompañar, así que esto dice cuántos canales están en uso y no qué
            // hacer con ellos. Que dos Tracks compartan uno es legítimo; el
            // número solo lo hace visible.
            Text("\(inUse) of \(Pattern.trackCount) distinct")
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
        }
    }

    /// Cuántos canales distintos usan los doce Tracks.
    private var inUse: Int {
        Set(channels.prefix(Pattern.trackCount).map(\.number)).count
    }

    /// Una fila: **el Track a la izquierda, sus dieciséis canales a la derecha.**
    ///
    /// El rango es 1–16 porque es el del protocolo MIDI. Que la app tenga doce
    /// Tracks no hace desaparecer cuatro canales del hardware: los 13–16 dejan de
    /// asignarse solos, no de existir.
    private func row(for index: Int) -> some View {
        let channel = channels.indices.contains(index) ? channels[index] : .first
        let isSelectedTrack = index == selected

        return HStack(spacing: 12) {
            Text("Track \(index + 1)")
                .font(isSelectedTrack ? Typography.captionBold : Typography.caption)
                .monospacedDigit()
                .foregroundStyle(isSelectedTrack ? accent : Palette.mutedBright)
                .frame(width: 72, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Channel.validRange, id: \.self) { number in
                    button(number, of: channel, forTrack: index)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func button(_ number: Int, of channel: Channel, forTrack index: Int) -> some View {
        let isSelected = number == channel.number

        return Button("\(number)") { onChannelChange(index, Channel(number)!) }
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
