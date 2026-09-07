/// En qué estado está un hueco de Pattern.
///
/// **Bajó de la vista el 2026-09-07.** `PatternGrid.state(_:)` lo calculaba en
/// `App`, y su propia documentación decía por qué se quedaba arriba: «la premisa
/// de la cáscara —que solo existe el índice 0— es una limitación temporal de esta
/// pantalla, no una propiedad del dominio, y meterla en `Engine` sería grabar en
/// el motor puro algo que va a dejar de ser cierto».
///
/// Ha dejado de ser cierto: los 256 Patterns existen. El estado pasa a ser una
/// lectura directa y baja a donde hay tests, como la propia nota prometía.
public enum PatternSlotState: Equatable, Sendable, CaseIterable {

    /// Suena ahora mismo.
    case playing

    /// **Espera al próximo compás.** Es el estado que la rebanada añade: entre
    /// pulsar un Pattern y el compás en que entra pasa hasta un compás —cuatro
    /// segundos a 60 BPM— y sin decirlo la espera se lee como que el botón no
    /// funciona.
    case queued

    /// Tiene material y no suena.
    case ready

    /// No tiene material. **Es la palabra exacta**: el hueco existe y está
    /// vacío, no está «apagado por ahora».
    case empty

    /// Decide el estado a partir de lo que se sabe del hueco.
    ///
    /// **El que suena manda sobre el que espera.** Coinciden cuando alguien
    /// vuelve a pulsar el Pattern que ya suena: eso no es una espera, es no
    /// cambiar de sitio, y decir `queued` prometería un cambio que no va a
    /// ocurrir.
    ///
    /// **Y sin transporte no hay espera**: parado, el cambio de Pattern es
    /// inmediato (FR5), así que `queued` no puede darse.
    public init(hasMaterial: Bool, isPlaying: Bool, isQueued: Bool, isRunning: Bool) {
        guard hasMaterial else {
            self = .empty
            return
        }
        guard isRunning else {
            self = .ready
            return
        }
        if isPlaying {
            self = .playing
        } else if isQueued {
            self = .queued
        } else {
            self = .ready
        }
    }

    /// Cómo se escribe en pantalla. Sin traducir, como el resto del vocabulario.
    public var label: String {
        switch self {
        case .playing: "playing"
        case .queued: "queued"
        case .ready: "ready"
        case .empty: "empty"
        }
    }
}

extension Bank {

    /// El estado de los dieciséis huecos, de una vez.
    ///
    /// **Es como la pantalla lo necesita**: dieciséis estados, no dieciséis
    /// preguntas, por la misma razón que `patternsHavingMaterial` devuelve el
    /// array entero.
    public func slotStates(playing: Int?, queued: Int?, isRunning: Bool) -> [PatternSlotState] {
        (0..<Self.patternCount).map { index in
            PatternSlotState(
                hasMaterial: pattern(at: index)?.hasMaterial ?? false,
                isPlaying: index == playing,
                isQueued: index == queued,
                isRunning: isRunning
            )
        }
    }
}
