import Engine
import SwiftUI

/// La pantalla `scale`: el marco tonal del Track seleccionado y su pool.
///
/// **Aquí el dedo sí opera** (FR15–FR20). No contradice al principio rector: lo
/// que `product-guidelines.md` protege es que no haga falta mirar el iPad *para
/// tocar*, y esto se configura antes de tocar. La pantalla `track` es la que se
/// lee mientras suena, y ahí no se edita nada.
///
/// **Las tres piezas son las del handoff**, y cada una tiene su vista: elegir la
/// escala, elegir la raíz, y decidir qué alturas entran al pool.
struct ScaleScreen: View {

    let model: TransportModel

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                TrackContext(
                    selected: model.selectedTrackIndex,
                    onSelect: { model.selectTrack($0) }
                )

                ScalePicker(
                    scale: model.frame.scale,
                    onSelect: { model.setFrame(TonalFrame(scale: $0, root: model.frame.root)) }
                )

                RootPicker(
                    root: model.frame.root,
                    onSelect: { model.setFrame(TonalFrame(scale: model.frame.scale, root: $0)) }
                )

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PitchPoolGrid(
                surface: model.surface,
                pool: model.track.pool,
                onPress: { model.pressPad(at: $0) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// De qué Track se está editando el marco.
///
/// **Es un selector, no una etiqueta** (FR15). Scale, Root y el pool son
/// parámetros del Track: poder verlos sin poder elegir cuál obligaría a un viaje
/// de ida y vuelta a la pantalla `track` por cada uno de los doce.
///
/// > Se decidió primero que fuera solo contexto y se corrigió el mismo día: la
/// > regla acordada es que el dedo opera en todo salvo los parámetros
/// > generativos, y elegir qué Track se mira no es uno de ellos.
struct TrackContext: View {

    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display: "track")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)

            // **Una rejilla de doce y no un menú.** Se toca de pie: un menú
            // pediría dos gestos y apuntar a un renglón, y aquí los doce están a
            // un dedo de distancia — igual que en la franja de la pantalla
            // `track`, que es la otra vía y usa la misma forma.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
                spacing: 6
            ) {
                ForEach(0..<Pattern.trackCount, id: \.self) { index in
                    Button((index + 1).paddedForDisplay) { onSelect(index) }
                        .font(index == selected ? Typography.captionBold : Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(index == selected ? Palette.onAccent : Palette.mutedBright)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                        .brutalistControl(
                            accent: Palette.offWhite,
                            isSelected: index == selected,
                            radius: Brutalist.radiusSmall
                        )
                }
            }
        }
    }
}

/// Las escalas, en tarjetas.
///
/// **Son ocho y el handoff dibuja seis.** Las seis van primero y en su orden, así
/// que las dos filas de arriba son literalmente el PNG; las dos pentatónicas
/// cierran en un cuarto renglón. El orden lo declara `Scale.ordered`, para que el
/// knob y la pantalla no discrepen.
struct ScalePicker: View {

    let scale: Scale
    let onSelect: (Scale) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display: "scale")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 8
            ) {
                ForEach(Scale.ordered, id: \.self) { candidate in
                    let isSelected = candidate == scale

                    Button(action: { onSelect(candidate) }) {
                        Text(display: candidate.name)
                            .font(isSelected ? Typography.bodyStrong : Typography.body)
                            .foregroundStyle(isSelected ? Palette.onAccent : Palette.mutedBright)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // La escala elegida lleva el violeta de Tonal, que es su
                    // familia. El trazo de 3 pt lo pone `brutalistControl` al
                    // estar seleccionada.
                    .brutalistControl(accent: Palette.tonal, isSelected: isSelected)
                }
            }
        }
    }
}

/// La raíz: las doce clases de altura.
///
/// **La elegida va en off-white y no en violeta**, como el handoff. Es la
/// distinción que separa las dos decisiones de esta pantalla: la escala
/// pertenece a Tonal y se rellena con su acento; la raíz es «ésta entre iguales»
/// y usa el off-white que el sistema reserva para eso — el mismo del Track
/// elegido, el Cycle en curso y el subrayado del módulo activo.
struct RootPicker: View {

    let root: Root
    let onSelect: (Root) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display: "root")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
                spacing: 6
            ) {
                ForEach(0..<12, id: \.self) { value in
                    let candidate = Root(value)!
                    let isSelected = candidate == root

                    Button(action: { onSelect(candidate) }) {
                        Text(display: "\(candidate)")
                            .font(isSelected ? Typography.captionBold : Typography.caption)
                            .foregroundStyle(isSelected ? Palette.onAccent : Palette.mutedBright)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .brutalistControl(
                        accent: Palette.offWhite,
                        isSelected: isSelected,
                        radius: Brutalist.radiusSmall
                    )
                }
            }
        }
    }
}

/// El `pitch pool`: la rejilla 4×4, espejo de los pads del controlador.
///
/// **No es una rejilla de dieciséis notas** (FR18). `PadSurface` ya declara la
/// correspondencia y ésta la respeta posición por posición: siete grados, el pad
/// de bajar octava, siete grados de la octava siguiente, y el de subir. Catorce
/// pads de nota y dos de octava.
///
/// **Los pads de octava dicen en qué octava se está**, y ése es su segundo
/// papel: `PadSurface.octaveShift` no aparece en ninguna otra parte de la
/// interfaz, así que sin esto el usuario no tendría cómo saber a qué registro
/// está metiendo notas.
///
/// **Nunca van en violeta.** El violeta de Tonal significa «esta altura está en
/// el pool», y un pad de octava no es una altura. Teñirlos del mismo color los
/// haría parecer notas activas.
///
/// **Los pads son grados, no una melodía** (FR20). La rejilla dice qué alturas
/// están disponibles; nunca qué altura suena en qué step. Es la sección
/// «Representación tonal: pool, no melodía» de `product-guidelines.md`: PITCH
/// define un pool, no un piano-roll.
struct PitchPoolGrid: View {

    let surface: PadSurface
    let pool: PitchPool
    let onPress: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display: "pitch pool")
                        .font(Typography.parameterLine)
                        .foregroundStyle(Palette.tonal)

                    Text(display: "scale degrees")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                }

                Spacer(minLength: 12)

                // **En qué octava se está, una vez.**
                //
                // > Estuvo escrito en los dos pads de octava y se veía mal: el
                // > mismo dato repetido a cuatro filas de distancia, y encima
                // > pegado a los botones que lo cambian, como si cada uno
                // > anunciara adónde lleva. No lleva ahí: dice dónde estás.
                //
                // Sigue haciendo falta porque `PadSurface.octaveShift` no
                // aparece en ninguna otra parte de la interfaz: sin esto no hay
                // forma de saber a qué registro se están metiendo notas.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(display: "octave")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)

                    Text(display: octaveName)
                        .font(Typography.captionStrong)
                        .monospacedDigit()
                        .foregroundStyle(Palette.mutedBright)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<PadSurface.padCount, id: \.self) { index in
                    pad(index)
                }
            }

            // **El contador dice el número real, no un ocho fijo.**
            // `PitchPool.capacity` son ocho huecos y la rejilla ofrece catorce
            // candidatos, así que el noveno pad no entra. Un contador que dijera
            // siempre ocho mentiría justo cuando el usuario choca con el tope.
            Text(display: count)
                .font(Typography.caption)
                .foregroundStyle(pool.count >= PitchPool.capacity ? Palette.tonal : Palette.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: Brutalist.radiusLarge)
                .stroke(Palette.tonal, lineWidth: Brutalist.stroke)
        }
    }

    private var count: String {
        switch pool.count {
        case 0: "pool empty"
        case 1: "1 note active"
        default: "\(pool.count) notes active"
        }
    }

    @ViewBuilder
    private func pad(_ index: Int) -> some View {
        switch index {
        case PadSurface.octaveDownIndex:
            octave(index, symbol: "−", enabled: surface.canShiftDown)
        case PadSurface.octaveUpIndex:
            octave(index, symbol: "+", enabled: surface.canShiftUp)
        default:
            note(index)
        }
    }

    /// Un pad de nota: su altura, y si está en el pool.
    private func note(_ index: Int) -> some View {
        let pitch = surface.pitch(at: index)
        let isActive = pitch.map { pool.contains($0) } ?? false

        return Button(action: { onPress(index) }) {
            // **Un pad sin altura se dibuja vacío, no se rellena.** Con una
            // escala de cinco grados —`pentatonic`, `hirajoshi`— los pads 6, 7,
            // 14 y 15 se quedan sin grado. `PadSurface` documenta por qué no se
            // rellenan: pondría el pad 9 a una distancia distinta para cada
            // escala y la superficie dejaría de poder aprenderse.
            Text(display: pitch.map { "\($0)" } ?? "")
                .font(isActive ? Typography.bodyStrong : Typography.body)
                .foregroundStyle(isActive ? Palette.onAccent : Palette.mutedBright)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pitch == nil)
        .brutalistControl(accent: Palette.tonal, isSelected: isActive)
        .opacity(pitch == nil ? 0.35 : 1)
    }

    /// Un pad de octava: qué hace y dónde está.
    private func octave(_ index: Int, symbol: String, enabled: Bool) -> some View {
        Button(action: { onPress(index) }) {
            Text(display: "oct \(symbol)")
                .font(Typography.captionStrong)
                .foregroundStyle(enabled ? Palette.mutedBright : Palette.border)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // **Neutro, nunca violeta.** El violeta dice «esta altura está en el
        // pool», y esto no es una altura.
        .brutalistControl(accent: Palette.offWhite, isSelected: false, isPopulated: enabled)
    }

    /// La octava base vigente, leída de la propia superficie.
    ///
    /// **Sale del pad 1**, que es el grado 1 y por tanto el Root en la octava
    /// base: preguntárselo a la superficie es más honesto que recalcular el
    /// número a partir de `octaveShift` y una constante, que es la clase de
    /// duplicado que se descubre cuando los dos dejan de coincidir.
    private var octaveName: String {
        surface.pitch(at: 0).map { "\($0)" } ?? "—"
    }
}
