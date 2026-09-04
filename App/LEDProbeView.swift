import CoreMIDI
import MIDI
import SwiftUI

/// La pantalla de pruebas del feedback: qué sabe iluminar el controlador.
///
/// **Es instrumentación desechable y se borra al cerrar la Fase 1** del track
/// `controller-feedback_20260904`, como el panel del arnés de jitter antes de
/// que la pantalla del handoff lo quitara. Por eso no lleva tests y por eso vive
/// entera en `App`: nada de lo que hay aquí sobrevive a la fase, así que meterlo
/// en `MIDI` sería dejar en un paquete cubierto código que nace con fecha de
/// caducidad.
///
/// **Existe porque el repertorio del hardware es una pregunta abierta.** La
/// rebanada 7 enseñó a no dar por sabido el BeatStep Pro: lo que el código dé
/// por cierto del controlador tiene que haberse visto encender en el iPad. Si
/// nada se ilumina, el track se cierra aquí (NFR1).
///
/// Se abre con el flag de lanzamiento `--led-probe`, que se pone en el esquema
/// de Xcode. Sin él, la app arranca normal.
struct LEDProbeView: View {

    /// El flag que abre esta pantalla en lugar de la app.
    static let launchArgument = "--led-probe"

    /// Si el proceso arrancó pidiendo la sonda.
    static var isRequested: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    @State private var probe = LEDProbeModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    destinations
                    channels
                    notes
                    controlChanges
                    log
                }
                .padding(.bottom, 24)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
        .foregroundStyle(Palette.mutedBright)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("LED PROBE")
                .font(Typography.sectionTitle)
                .foregroundStyle(Palette.shape)
            Text("Instrumentación desechable · Fase 1")
                .font(Typography.caption)
            Spacer(minLength: 8)
            Text(probe.status)
                .font(Typography.captionStrong)
        }
    }

    // MARK: - Destino

    /// **Se elige un destino de la lista entera, sin derivarlo de la fuente.**
    /// Derivar el destino hermano es FR11 y es trabajo de la Fase 3; aquí lo que
    /// hace falta es poder apuntarle a cualquier cosa —incluido un sintetizador,
    /// para confirmar que la sonda envía de verdad cuando el controlador no
    /// responde—.
    private var destinations: some View {
        section("Destino") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(probe.destinations, id: \.self) { destination in
                    Button {
                        probe.select(destination)
                    } label: {
                        Text(destination.displayName)
                            .font(Typography.body)
                            .foregroundStyle(
                                probe.isSelected(destination)
                                    ? Palette.toolbar : Palette.mutedBright
                            )
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .brutalistControl(
                        accent: Palette.shape, isSelected: probe.isSelected(destination))
                }

                Button("Refrescar la lista") { probe.refreshDestinations() }
                    .font(Typography.caption)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .brutalistControl(accent: Palette.shape, isSelected: false)
            }
        }
    }

    // MARK: - Canal

    /// El canal es la primera sospecha cuando no se enciende nada: el BeatStep
    /// escucha por el que tenga configurado, que no tiene por qué ser el de
    /// ningún Track (FR12).
    private var channels: some View {
        section("Canal") {
            row(1...16, isSelected: { $0 == probe.channel }) { number in
                probe.channel = number
            }
        }
    }

    // MARK: - Notas

    private var notes: some View {
        section("Pads · note-on / note-off") {
            VStack(alignment: .leading, spacing: 12) {
                blockHeader(
                    label: "Primera nota",
                    value: probe.noteBase,
                    onChange: { probe.noteBase = $0 }
                )

                labelled("Velocity") {
                    row(probe.velocities, isSelected: { $0 == probe.velocity }) {
                        probe.velocity = $0
                    }
                }

                labelled("Note-on") {
                    grid(probe.noteNumbers) { probe.sendNoteOn($0) }
                }

                labelled("Note-off") {
                    grid(probe.noteNumbers) { probe.sendNoteOff($0) }
                }

                Button("Barrer: note-off a los dieciséis") { probe.sweepNotesOff() }
                    .font(Typography.caption)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .brutalistControl(accent: Palette.groove, isSelected: false)
            }
        }
    }

    // MARK: - Control changes

    private var controlChanges: some View {
        section("Step buttons · control change") {
            VStack(alignment: .leading, spacing: 12) {
                blockHeader(
                    label: "Primer CC",
                    value: probe.controllerBase,
                    onChange: { probe.controllerBase = $0 }
                )

                labelled("Valor") {
                    row(probe.controllerValues, isSelected: { $0 == probe.controllerValue }) {
                        probe.controllerValue = $0
                    }
                }

                labelled("Enviar") {
                    grid(probe.controllerNumbers) { probe.sendControlChange($0) }
                }
            }
        }
    }

    // MARK: - El registro

    /// **Lo que se envió, en orden y uno por línea.**
    ///
    /// El descubrimiento se hace mirando el controlador, no leyendo esto; el
    /// registro está para poder decir *qué* mensaje fue el que encendió algo
    /// cuando ya se encendió, que es lo que después se escribe en
    /// `device-verification.md`.
    private var log: some View {
        section("Enviado") {
            VStack(alignment: .leading, spacing: 4) {
                if probe.log.isEmpty {
                    Text("Todavía nada.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                }
                ForEach(Array(probe.log.enumerated()), id: \.offset) { entry in
                    Text(entry.element)
                        .font(Typography.caption)
                        .foregroundStyle(entry.offset == 0 ? Palette.shape : Palette.muted)
                }
            }
        }
    }

    // MARK: - Piezas de la pantalla

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Typography.captionBold)
                .foregroundStyle(Palette.mutedBright)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brutalistPanel()
    }

    private func labelled<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
            content()
        }
    }

    /// Mueve el primer número del bloque, para explorar fuera de lo que el
    /// preset declara: si los pads no responden en 36, la siguiente pregunta es
    /// en cuál sí.
    private func blockHeader(
        label: String, value: Int, onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text("\(label): \(value)")
                .font(Typography.bodyMedium)
                .frame(minWidth: 160, alignment: .leading)
            ForEach([-12, -1, 1, 12], id: \.self) { delta in
                Button(delta > 0 ? "+\(delta)" : "\(delta)") {
                    onChange(value + delta)
                }
                .font(Typography.captionStrong)
                .buttonStyle(.plain)
                .frame(width: 56, height: 40)
                .brutalistControl(accent: Palette.shape, isSelected: false)
            }
        }
    }

    private func row(
        _ numbers: some Sequence<Int>, isSelected: @escaping (Int) -> Bool,
        onTap: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(numbers), id: \.self) { number in
                Button("\(number)") { onTap(number) }
                    .font(Typography.captionStrong)
                    .foregroundStyle(isSelected(number) ? Palette.toolbar : Palette.mutedBright)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .brutalistControl(accent: Palette.tonal, isSelected: isSelected(number))
            }
        }
    }

    /// Los dieciséis del bloque, en dos filas de ocho como en el controlador.
    private func grid(_ numbers: [Int], onTap: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { half in
                HStack(spacing: 6) {
                    ForEach(numbers[(half * 8)..<(half * 8 + 8)], id: \.self) { number in
                        Button("\(number)") { onTap(number) }
                            .font(Typography.captionStrong)
                            .buttonStyle(.plain)
                            .frame(minWidth: 56, minHeight: 48)
                            .brutalistControl(accent: Palette.shape, isSelected: false)
                    }
                }
            }
        }
    }
}

/// El estado de la sonda: a dónde manda, qué manda y qué mandó.
///
/// **Manda un mensaje por gesto, y ninguno solo.** Descubrir qué ilumina el
/// controlador es mirar el controlador mientras se pulsa una cosa: una ráfaga
/// automática dejaría encendido algo sin saber cuál de los mensajes lo hizo.
/// La única excepción es el barrido de note-offs, que es la forma de volver a
/// dejarlo a oscuras.
@Observable
@MainActor
final class LEDProbeModel {

    /// Las velocities que se prueban: el mínimo audible, la mitad y el máximo.
    /// Si el pad cambia de color o de brillo, es aquí donde se ve.
    let velocities = [1, 32, 64, 100, 127]

    /// Los valores de CC que se prueban. **El 1 está a propósito**: en muchos
    /// controladores el LED distingue «encendido» de «parpadeando» por el valor,
    /// y un salto de 0 a 127 se saltaría los estados intermedios.
    let controllerValues = [0, 1, 2, 16, 64, 127]

    var channel = 1
    var velocity = 100
    var controllerValue = 127

    /// Primera nota del bloque de pads. Arranca en la que declara el preset.
    var noteBase = Int(ControlMapping.beatStepPro.padBlock.value) {
        didSet { noteBase = Self.clampBlock(noteBase) }
    }

    /// Primer CC del bloque de step buttons. Arranca en el del preset.
    var controllerBase = ControlMapping.beatStepPro.stepButtonBlock.number {
        didSet { controllerBase = Self.clampBlock(controllerBase) }
    }

    var noteNumbers: [Int] { block(from: noteBase) }
    var controllerNumbers: [Int] { block(from: controllerBase) }

    private(set) var destinations: [MIDIEndpointInfo] = []
    private(set) var selected: MIDIEndpointInfo?

    /// Lo enviado, lo más reciente primero.
    private(set) var log: [String] = []

    /// Por qué no se puede enviar, o a dónde se está enviando.
    var status: String {
        if let failure { return failure }
        guard let selected else { return "Sin destino elegido" }
        return "→ \(selected.displayName) · canal \(channel)"
    }

    private var failure: String?
    private let output: CoreMIDIOutput?

    init() {
        do {
            output = try CoreMIDIOutput(clientName: "Torax H-0 LED probe")
        } catch {
            output = nil
            failure = "CoreMIDI no arrancó: \(error)"
        }
        refreshDestinations()
    }

    func refreshDestinations() {
        guard let output else { return }
        destinations = output.availableDestinations()
        // Si el destino elegido desapareció, se suelta: enviarle a un endpoint
        // muerto no da error (`CoreMIDIOutput.classify`), así que la sonda
        // parecería estar mandando.
        if let selected, !destinations.contains(selected) {
            self.selected = nil
        }
    }

    func select(_ destination: MIDIEndpointInfo) { selected = destination }

    func isSelected(_ destination: MIDIEndpointInfo) -> Bool { selected == destination }

    func sendNoteOn(_ note: Int) {
        guard let channel = MIDIChannel(channel), let note = MIDINote(note),
            let velocity = MIDIVelocity(velocity)
        else { return }
        send(
            .noteOn(channel: channel, note: note, velocity: velocity),
            describedAs: "note-on \(note.value) vel \(velocity.value)")
    }

    func sendNoteOff(_ note: Int) {
        guard let channel = MIDIChannel(channel), let note = MIDINote(note),
            let velocity = MIDIVelocity(0)
        else { return }
        send(
            .noteOff(channel: channel, note: note, velocity: velocity),
            describedAs: "note-off \(note.value)")
    }

    /// Deja el controlador a oscuras sin tener que pulsar dieciséis veces.
    func sweepNotesOff() {
        for note in noteNumbers { sendNoteOff(note) }
    }

    func sendControlChange(_ controller: Int) {
        guard let channel = MIDIChannel(channel), let controller = MIDIController(controller),
            let value = UInt8(exactly: controllerValue)
        else { return }
        send(
            .controlChange(channel: channel, controller: controller, value: value),
            describedAs: "CC \(controller.number) = \(value)")
    }

    /// Envía ahora mismo.
    ///
    /// **Timestamp cero, que en CoreMIDI significa «ya».** La sonda no programa
    /// nada en el futuro: lo que se está averiguando es si el hardware responde,
    /// no cuándo. Sellar con el reloj del scheduler es FR6 y es de la Fase 4.
    private func send(_ message: MIDIMessage, describedAs description: String) {
        guard let output, let selected else { return }
        let result = output.send(message, to: selected.endpoint, atHostTime: 0)
        record("canal \(channel) · \(description)" + (result == .sent ? "" : " · \(result)"))
    }

    /// Guarda las últimas líneas y descarta el resto: la pantalla no es un
    /// historial, es lo que acaba de pasar.
    private func record(_ line: String) {
        log.insert(line, at: 0)
        if log.count > 12 { log.removeLast(log.count - 12) }
    }

    private func block(from base: Int) -> [Int] {
        (0..<ControlMapping.controlsPerFamily).map { base + $0 }
    }

    /// El bloque entero tiene que caber en 0–127, o los últimos pads mandarían
    /// números inválidos y el gesto no haría nada sin decir por qué.
    private static func clampBlock(_ base: Int) -> Int {
        min(max(base, 0), 127 - ControlMapping.controlsPerFamily + 1)
    }
}
