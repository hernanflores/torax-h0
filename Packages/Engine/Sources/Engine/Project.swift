/// Dieciséis Banks y dónde se quedó el usuario.
///
/// **Es la raíz del árbol de la Pre Spec**: «Project: estado completo del
/// proyecto: 16 Banks, sus Patterns/Tracks y ajustes asociados». Con `Bank`
/// debajo, el árbol queda entero — Project › 16 Banks › 16 Patterns › 12 Tracks
/// › 16 Cycles — y es lo que la persistencia escribe.
///
/// **Es la única parte del modelo que no es material.** Todo lo que cuelga de
/// aquí es lo que suena; el Project añade dos cosas que no:
///
/// - **Dónde se estaba mirando**: qué Bank, qué Pattern y qué Track. Es lo que
///   la Pre Spec pide por su nombre cuando dice que el Autosave «restaura el
///   último Bank tras reiniciar».
/// - **Los ajustes de sesión**: qué reloj manda y a qué hardware se hablaba.
///
/// **Lo que no guarda: mute y solo.** Son mezcla y no material, y la nota del
/// 2026-09-02 de la Pre Spec ya los deja fuera del árbol — «viven por encima, en
/// una capa que no se guarda con el material».
///
/// **Tampoco es un dato de tiempo real**, por la misma razón que `Bank`: lo que
/// cruza al hilo del scheduler es un `Pattern`. Con 256 Patterns dentro,
/// pretender que fuera trivial serían unos 9,5 MB de valor moviéndose por la
/// pila.
public struct Project: Equatable, Sendable {

    /// Cuántos Banks tiene un Project. La Pre Spec: «16 Banks».
    public static let bankCount = 16

    private var banks: [Bank]

    /// El Bank que se está mirando, 0–15.
    public let selectedBank: Int

    /// El Pattern que se está mirando dentro de ese Bank, 0–15.
    public let selectedPattern: Int

    /// El Track seleccionado, 0–11.
    ///
    /// **Se acota contra los doce del `Pattern`, no contra dieciséis.** Es la
    /// desviación de legibilidad anotada el 2026-09-02, y aquí también manda.
    public let selectedTrack: Int

    /// Quién manda el tempo.
    public let clockSource: ClockSource

    /// El nombre del destino MIDI elegido, o `nil` si no hay ninguno.
    ///
    /// **Se guarda el nombre y no el endpoint.** Un `MIDIEndpointRef` es un
    /// handle de runtime que no significa nada en el arranque siguiente —y es de
    /// CoreMIDI, que este paquete no puede ver—. Que el nombre no case con nada
    /// al abrir es un estado esperado y no un error: `MIDIEndpointSelection` ya
    /// trata la desconexión así.
    public let destinationName: String?

    /// El nombre de la fuente MIDI elegida, o `nil`.
    public let sourceName: String?

    /// El mapeo del controlador, en números, o `nil` si nunca se aprendió nada.
    ///
    /// **Ausente significa el preset de fábrica** (`midi-learn_20260908`, FR16 y
    /// FR17): no haber aprendido es un estado válido, no un campo que falte —
    /// el mismo criterio que `destinationName`. Y es lo que permite que un
    /// fichero escrito antes de MIDI Learn abra sin migrador y sin subir
    /// `schemaVersion`.
    ///
    /// **En números y no en tipos de CoreMIDI**, por lo mismo que el destino se
    /// guarda por su nombre: este paquete no puede ver CoreMIDI. `MIDI` lo
    /// convierte en las dos direcciones.
    public let controlNumbers: ControlNumbers?

    /// Un Project entero vacío, mirando al primer hueco, con reloj interno y sin
    /// hardware recordado.
    public init() {
        banks = Array(repeating: Bank(), count: Self.bankCount)
        selectedBank = 0
        selectedPattern = 0
        selectedTrack = 0
        clockSource = .internal
        destinationName = nil
        sourceName = nil
        controlNumbers = nil
    }

    /// El constructor completo, interno: fuera se llega por los métodos de
    /// abajo, que son los que garantizan los rangos.
    init(
        banks: [Bank],
        selectedBank: Int,
        selectedPattern: Int,
        selectedTrack: Int,
        clockSource: ClockSource,
        destinationName: String?,
        sourceName: String?,
        controlNumbers: ControlNumbers? = nil
    ) {
        precondition(banks.count == Self.bankCount)
        self.banks = banks
        self.selectedBank = selectedBank
        self.selectedPattern = selectedPattern
        self.selectedTrack = selectedTrack
        self.clockSource = clockSource
        self.destinationName = destinationName
        self.sourceName = sourceName
        self.controlNumbers = controlNumbers
    }

    /// El Project con el que arranca la app: el material de siempre en el
    /// **primer hueco**, y los otros 255 vacíos.
    ///
    /// **Meter dos niveles no cambia lo que se oye al abrir.** Es el mismo
    /// requisito que Cycles se puso a sí mismo cuando pasó de un juego de
    /// parámetros a dieciséis: la app suena exactamente como sonaba hasta que
    /// alguien use lo que la rebanada añade.
    public static let initial = Project().replacing(
        Bank().replacing(Pattern.initial, at: 0),
        at: 0
    )

    /// El Bank de esa posición, o `nil` fuera de 0–15.
    public func bank(at index: Int) -> Bank? {
        guard (0..<Self.bankCount).contains(index) else { return nil }
        return banks[index]
    }

    /// El Project con ese Bank en esa posición y los otros quince intactos.
    /// Fuera de rango devuelve el Project tal cual.
    public func replacing(_ bank: Bank, at index: Int) -> Project {
        guard (0..<Self.bankCount).contains(index) else { return self }

        var updated = banks
        updated[index] = bank
        return copy(banks: updated)
    }

    /// Mirar otro Bank. **Se acota, no envuelve**: pedir el 20 deja el 16.
    ///
    /// Envolver convertiría un índice corrupto en disco en una selección
    /// plausible, que es peor que quedarse en el borde. Es el criterio que
    /// `Pulses` y `Time` ya siguen.
    public func selectingBank(_ index: Int) -> Project {
        copy(selectedBank: Self.clamped(index, to: Self.bankCount))
    }

    /// Mirar otro Pattern, con el mismo criterio.
    public func selectingPattern(_ index: Int) -> Project {
        copy(selectedPattern: Self.clamped(index, to: Bank.patternCount))
    }

    /// Seleccionar otro Track, acotado contra los doce del `Pattern`.
    public func selectingTrack(_ index: Int) -> Project {
        copy(selectedTrack: Self.clamped(index, to: Pattern.trackCount))
    }

    /// El mismo Project siguiendo otro reloj.
    public func withClockSource(_ source: ClockSource) -> Project {
        copy(clockSource: source)
    }

    /// El mismo Project recordando —o dejando de recordar— a qué hardware se
    /// hablaba. `nil` en cualquiera de los dos es un estado válido.
    public func remembering(destinationNamed destination: String?, sourceNamed source: String?)
        -> Project
    {
        copy(destinationName: .some(destination), sourceName: .some(source))
    }

    /// El mismo Project recordando —o dejando de recordar— el mapeo aprendido.
    ///
    /// `nil` es un estado válido y significa el preset de fábrica: es la vuelta
    /// atrás de FR18, y también lo que un Project que nunca aprendió nada tiene.
    public func remembering(controlNumbers numbers: ControlNumbers?) -> Project {
        copy(controlNumbers: .some(numbers))
    }

    /// El Project con ese Pattern en ese hueco del **Bank vigente**, y los otros
    /// quince intactos.
    ///
    /// **El material entra como valor, no como índice.** Es lo que el pegado
    /// entre Banks necesita (FR22): el Pattern del portapapeles puede venir de
    /// otro Banco, donde el hueco 3 contiene otra cosa, así que no hay origen
    /// que nombrar. Sustituye lo que hubiera, sin mezcla. Fuera de rango
    /// devuelve el Project tal cual.
    public func replacing(_ pattern: Pattern, at index: Int) -> Project {
        guard let bank = bank(at: selectedBank) else { return self }
        guard (0..<Bank.patternCount).contains(index) else { return self }
        return replacing(bank.replacing(pattern, at: index), at: selectedBank)
    }

    /// El Project con el Pattern de `origin` copiado en `destination`, ambos
    /// dentro del **Bank vigente**.
    ///
    /// **Las dos puntas son explícitas, y ese es el arreglo.** Con el origen
    /// implícito —el hueco seleccionado— la pantalla, que solo conoce un índice,
    /// acababa pasando ese mismo índice como destino: la celda se copiaba sobre
    /// sí misma y no cambiaba nada. Pedir el origen hace que el error no se
    /// pueda escribir.
    ///
    /// Copiar un hueco sobre sí mismo sigue sin cambiar nada, pero ahora es una
    /// decisión y no un accidente. Fuera de rango, en cualquiera de las dos
    /// puntas, devuelve el Project tal cual.
    public func copyingPattern(from origin: Int, to destination: Int) -> Project {
        guard let bank = bank(at: selectedBank) else { return self }
        return replacing(bank.copyingPattern(from: origin, to: destination), at: selectedBank)
    }

    /// El Project con ese hueco del Bank vigente vacío.
    ///
    /// Fuera de rango devuelve el Project tal cual.
    public func clearingPattern(at index: Int) -> Project {
        guard let bank = bank(at: selectedBank) else { return self }
        return replacing(bank.clearingPattern(at: index), at: selectedBank)
    }

    /// Acota a `0..<count`. No envuelve.
    private static func clamped(_ index: Int, to count: Int) -> Int {
        min(max(index, 0), count - 1)
    }

    /// **Existe para que cambiar un campo no obligue a reescribir los otros
    /// seis.** Reconstruir un valor a mano en cada método es la forma clásica de
    /// perder uno en silencio — la advertencia que `Cycle.applying(_:to:)` ya
    /// lleva escrita.
    ///
    /// Los dos opcionales van envueltos en un `Optional` de más para poder
    /// distinguir «no lo cambies» de «ponlo a `nil`».
    private func copy(
        banks: [Bank]? = nil,
        selectedBank: Int? = nil,
        selectedPattern: Int? = nil,
        selectedTrack: Int? = nil,
        clockSource: ClockSource? = nil,
        destinationName: String?? = nil,
        sourceName: String?? = nil,
        controlNumbers: ControlNumbers?? = nil
    ) -> Project {
        Project(
            banks: banks ?? self.banks,
            selectedBank: selectedBank ?? self.selectedBank,
            selectedPattern: selectedPattern ?? self.selectedPattern,
            selectedTrack: selectedTrack ?? self.selectedTrack,
            clockSource: clockSource ?? self.clockSource,
            destinationName: destinationName ?? self.destinationName,
            sourceName: sourceName ?? self.sourceName,
            controlNumbers: controlNumbers ?? self.controlNumbers
        )
    }
}
