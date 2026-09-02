import Engine
import SwiftUI

/// Los doce Tracks: cuál se edita y cuáles tienen material.
///
/// **Es la fila de selección, no la representación del patrón.** Esa son los
/// anillos concéntricos, que viven en su propia columna; aquí solo se dice cuál
/// se edita, sin adivinarlo.
///
/// **Seleccionar desde aquí hace lo mismo que su step button.** Sin controlador
/// conectado es la única vía, y con controlador las dos llevan al mismo sitio:
/// si no, la pantalla mentiría sobre lo que el hardware acaba de hacer.
struct TrackSelectorView: View {

    let selected: Int
    /// Cuáles tienen material. Un Track vacío dispara y no suena, así que la
    /// diferencia importa antes de preguntarse por qué no se oye.
    let hasMaterial: [Bool]
    /// El acento de la familia activa, que es el que lleva el elegido (FR5).
    let accent: Color
    let onSelect: (Int) -> Void

    /// Cuántos Cycles recorre el Track seleccionado.
    let activeCycles: Int
    /// Cuál se está editando: al que escuchan los knobs y los pads.
    let editingCycle: Int
    /// Cuál está sonando, o `nil` con el transporte parado.
    ///
    /// **Es un cierre y no un valor** porque deriva del reloj: se pregunta al
    /// dibujar, como los playheads. Un valor pasado por parámetro se quedaría
    /// congelado en el instante en que se compuso la vista.
    let cycleInCourse: () -> Int?
    let onActiveCyclesChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selector
            cyclesRow
        }
    }

    // MARK: - Los doce

    /// **Una fila**, no dos de seis.
    ///
    /// Dos filas se leerían como dos grupos y los Tracks no están agrupados: el
    /// 6 y el 7 son tan contiguos como el 3 y el 4. En una fila el orden es el
    /// mismo que el de los step buttons del controlador, que es la superficie
    /// desde la que se seleccionan de verdad.
    ///
    /// **Cuántas hay lo dice `Pattern.trackCount`**, no un literal: la fila
    /// dibujaba dieciséis cuando ya había doce Tracks y las cuatro últimas eran
    /// botones muertos.
    private var selector: some View {
        HStack(spacing: 6) {
            ForEach(0..<Pattern.trackCount, id: \.self) { index in
                button(for: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Una pastilla: **su número, y nada más**.
    ///
    /// > **Perdió el canal el 2026-09-02.** La pastilla escribía debajo el canal
    /// > del Track en pequeño, y como el Track N arranca en el canal N eso era
    /// > el mismo número dos veces: un dato que no informaba y ocupaba alto.
    /// > El canal se edita ahora en la pantalla MIDI, donde se ven los doce a la
    /// > vez y un choque de canales se detecta sin ir Track por Track.
    ///
    /// Los tres estados se leen sin texto: el elegido va relleno del acento de
    /// la familia activa, los que tienen material llevan ese acento en el trazo,
    /// y los vacíos solo el borde en reposo.
    private func button(for index: Int) -> some View {
        let isSelected = index == selected
        let sounds = hasMaterial.indices.contains(index) && hasMaterial[index]

        return Button {
            onSelect(index)
        } label: {
            Text("\(index + 1)")
                .font(isSelected ? Typography.bodyStrong : Typography.body)
                .foregroundStyle(
                    isSelected ? Palette.toolbar : (sounds ? accent : Palette.muted)
                )
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .brutalistControl(
            accent: accent,
            isSelected: isSelected,
            isPopulated: sounds,
            radius: Brutalist.radius
        )
    }

    /// Los dieciséis Cycles del Track seleccionado: cuántos hay, cuál suena y
    /// cuál se edita (FR11).
    ///
    /// **Una sola fila hace las tres cosas**, y por eso se lee de un vistazo:
    /// pulsar el número N deja N Cycles activos, el que suena va relleno y el
    /// que se edita va con el contorno duro. Tres filas separadas —una para el
    /// número, otra para el cursor de reproducción, otra para el de edición—
    /// dirían lo mismo ocupando el triple y obligarían a cruzarlas con la
    /// vista.
    ///
    /// **El relleno se mueve con el reloj y el contorno con el knob**, que es
    /// exactamente la distinción de FR7 puesta donde se ve: si los dos
    /// coinciden, es que se está editando lo que suena.
    ///
    /// Los que quedan fuera del rango activo se dibujan apagados en vez de
    /// desaparecer: si la fila cambiara de longitud, los números se moverían de
    /// sitio y dejarían de poder pulsarse sin mirar.
    private var cyclesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Cycles · Track \(selected + 1)")
            // **Diez veces por segundo, no sesenta.** El relleno se mueve cuando
            // cierra una vuelta, que a los tempos de la app son segundos: pedir
            // un repintado por fotograma para eso sería carga visual sin nada
            // que enseñar. Los anillos sí van a `.animation`, porque ahí lo que
            // se mueve es continuo.
            //
            // La posición sigue saliendo del reloj musical y no del
            // temporizador: lo único que este decide es cuándo volver a
            // preguntar.
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let sounding = cycleInCourse()
                HStack(spacing: 6) {
                    ForEach(1...Track.cycleCount, id: \.self) { number in
                        cycleButton(number, sounding: sounding)
                    }
                }
            }
        }
    }

    private func cycleButton(_ number: Int, sounding: Int?) -> some View {
        let index = number - 1
        let isActive = number <= activeCycles
        let isSounding = index == sounding && isActive
        let isEditing = index == editingCycle && isActive

        return Button("\(number)") { onActiveCyclesChange(number) }
            .font(isSounding || isEditing ? Typography.captionBold : Typography.caption)
            .monospacedDigit()
            .foregroundStyle(cycleForeground(isActive: isActive, isSounding: isSounding))
            .frame(minWidth: 34, minHeight: 44)
            .brutalistControl(
                accent: accent,
                isSelected: isSounding,
                radius: Brutalist.radiusSmall
            )
            // El contorno del Cycle en edición va **encima** del control, para
            // que se distinga del relleno del que suena aunque sean el mismo.
            .overlay {
                if isEditing {
                    RoundedRectangle(cornerRadius: Brutalist.radiusSmall)
                        .strokeBorder(accent, lineWidth: Brutalist.strokeEmphasis)
                }
            }
            .opacity(isActive ? 1 : 0.35)
    }

    private func cycleForeground(isActive: Bool, isSounding: Bool) -> Color {
        guard isActive else { return Palette.muted }
        return isSounding ? Palette.toolbar : Palette.mutedBright
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Typography.captionStrong)
            .foregroundStyle(Palette.muted)
    }
}
