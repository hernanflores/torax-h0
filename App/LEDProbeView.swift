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
                    sysEx
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
                    onMove: { probe.moveNoteBase(by: $0) }
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
                    onMove: { probe.moveControllerBase(by: $0) }
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

    // MARK: - SysEx

    /// **La segunda vuelta: el frame de color del MiniLab MkII, sobre el Pro.**
    ///
    /// La cabecera de Arturia y la dirección `02 00` son las mismas que el Pro
    /// sí acepta para configurarse; que la subdirección de los pads exista aquí
    /// no lo ha publicado nadie. Esto es lo que lo resuelve, en un sentido o en
    /// el otro.
    private var sysEx: some View {
        section("SysEx") {
            VStack(alignment: .leading, spacing: 12) {
                labelled("Color") {
                    HStack(spacing: 6) {
                        ForEach(probe.sysExColors, id: \.1) { name, value in
                            Button("\(name) \(value)") { probe.sysExColor = value }
                                .font(Typography.captionStrong)
                                .foregroundStyle(
                                    probe.sysExColor == value
                                        ? Palette.toolbar : Palette.mutedBright
                                )
                                .buttonStyle(.plain)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .brutalistControl(
                                    accent: Palette.tonal, isSelected: probe.sysExColor == value)
                        }
                    }
                }

                labelled("Frame del MiniLab, por pad") {
                    grid(Array(0..<16)) { probe.sendPadColour($0) }
                }

                labelled("Bytes en crudo") {
                    HStack(spacing: 8) {
                        TextField("F0 … F7", text: $probe.sysExText)
                            .font(Typography.body)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .frame(minWidth: 420, minHeight: 44)
                            .brutalistPanel(radius: Brutalist.radius)

                        Button("Enviar") { probe.sendTypedSysEx() }
                            .font(Typography.captionStrong)
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .brutalistControl(accent: Palette.groove, isSelected: false)
                    }
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
        label: String, value: Int, onMove: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text("\(label): \(value)")
                .font(Typography.bodyMedium)
                .frame(minWidth: 160, alignment: .leading)
            ForEach([-12, -1, 1, 12], id: \.self) { delta in
                Button(delta > 0 ? "+\(delta)" : "\(delta)") {
                    onMove(delta)
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
    ///
    /// **El acotado vive en `move(_:by:)` y no en un `didSet`.** Con
    /// `@Observable`, la propiedad almacenada pasa a ser computada y el
    /// observador se queda sobre el respaldo: asignarse a sí misma desde el
    /// `didSet` vuelve a entrar por el setter y desborda la pila. Lo hizo, en
    /// dispositivo — `EXC_BAD_ACCESS (code=2)` en la página de guarda — al
    /// pulsar los botones que mueven el bloque.
    private(set) var noteBase = Int(ControlMapping.beatStepPro.padBlock.value)

    /// Primer CC del bloque de step buttons. Arranca en el del preset.
    private(set) var controllerBase = ControlMapping.beatStepPro.stepButtonBlock.number

    /// Mueve el primer número del bloque de pads, sin salirse de 0–127.
    func moveNoteBase(by delta: Int) {
        noteBase = Self.clampBlock(noteBase + delta)
    }

    /// Mueve el primer número del bloque de step buttons.
    func moveControllerBase(by delta: Int) {
        controllerBase = Self.clampBlock(controllerBase + delta)
    }

    var noteNumbers: [Int] { block(from: noteBase) }
    var controllerNumbers: [Int] { block(from: controllerBase) }

    /// Un destino del sistema, con el nombre que enseña la lista.
    struct Destination: Hashable, Identifiable {
        let endpoint: MIDIEndpointRef
        let displayName: String
        var id: MIDIEndpointRef { endpoint }
    }

    private(set) var destinations: [Destination] = []
    private(set) var selected: Destination?

    /// Lo enviado, lo más reciente primero.
    private(set) var log: [String] = []

    /// Por qué no se puede enviar, o a dónde se está enviando.
    var status: String {
        if let failure { return failure }
        guard let selected else { return "Sin destino elegido" }
        return "→ \(selected.displayName) · canal \(channel)"
    }

    // MARK: - SysEx

    /// Los colores que documenta el MiniLab MkII, por si el Pro comparte la
    /// dirección. Nadie ha publicado que la comparta: es la conjetura que esta
    /// segunda vuelta viene a resolver.
    let sysExColors = [
        ("negro", 0), ("rojo", 1), ("verde", 4), ("amarillo", 5),
        ("azul", 16), ("magenta", 17), ("cian", 20), ("blanco", 127),
    ]

    var sysExColor = 1

    /// Los bytes que se van a mandar, en hexadecimal y editables a mano.
    ///
    /// **A mano y en crudo a propósito.** No se sabe qué frame funciona —si es
    /// que alguno lo hace—, así que la sonda no puede ofrecer una lista cerrada:
    /// lo que hace falta es poder teclear cualquier cosa y ver si el
    /// controlador reacciona.
    var sysExText = LEDProbeModel.miniLabPadFrame

    /// El frame de color de pad del MiniLab MkII, con el pad 0 en rojo.
    ///
    /// `F0 00 20 6B 7F 42 02 00 10 7n cc F7` — `7n` el pad, `cc` el color. La
    /// cabecera `00 20 6B` es la de Arturia y la dirección `02 00` es la misma
    /// que el Pro sí usa para su propia configuración (`02 00 06` cambia los
    /// knobs entre absoluto y relativo). Que la dirección `10` de los pads
    /// exista también en el Pro es plausible, no seguro.
    static let miniLabPadFrame = "F0 00 20 6B 7F 42 02 00 10 70 01 F7"

    /// Manda el frame del MiniLab para un pad y el color elegido.
    func sendPadColour(_ pad: Int) {
        let bytes: [UInt8] = [
            0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x02, 0x00, 0x10,
            UInt8(0x70 + pad), UInt8(sysExColor), 0xF7,
        ]
        sendSysEx(bytes, describedAs: "SysEx pad \(pad) color \(sysExColor)")
    }

    /// Manda lo que haya escrito en el campo, sea lo que sea.
    func sendTypedSysEx() {
        guard let bytes = Self.parseHex(sysExText) else {
            record("SysEx: no se entiende «\(sysExText)»")
            return
        }
        guard bytes.first == 0xF0, bytes.last == 0xF7 else {
            record("SysEx: tiene que empezar en F0 y terminar en F7")
            return
        }
        sendSysEx(bytes, describedAs: "SysEx \(bytes.count) bytes")
    }

    private func sendSysEx(_ bytes: [UInt8], describedAs description: String) {
        send(bytes, describedAs: description)
    }

    private var failure: String?

    /// El único cliente de CoreMIDI de la sonda, con su puerto de salida.
    ///
    /// **Uno solo, y crudo.** La sonda usaba `CoreMIDIOutput` para las notas y
    /// abría un segundo cliente para el SysEx —el camino de la app manda un word
    /// de MIDI 1.0 dentro de un `MIDIEventList`, que no da para un mensaje de
    /// longitud arbitraria—. Con los dos en el proceso, el primero falló:
    /// `clientCreationFailed(-304)`, visto en el simulador. Un cliente propio
    /// que mande las dos cosas por la API de paquetes clásica lo evita, y de
    /// paso quita capas de en medio: lo que se está averiguando es si el
    /// hardware responde, no si el camino de la app funciona —eso ya está
    /// cubierto por sus tests—.
    ///
    /// **Vive en una caja sin aislamiento** para poder soltar los handles en
    /// `deinit`, que no puede tocar las propiedades de un modelo aislado al
    /// hilo principal.
    private final class Port {
        private var client = MIDIClientRef()
        private(set) var port: MIDIPortRef?
        private(set) var failure: String?

        init() {
            let clientStatus = MIDIClientCreate(
                "Torax H-0 LED probe" as CFString, nil, nil, &client)
            guard clientStatus == noErr else {
                failure = "CoreMIDI no arrancó: cliente \(clientStatus)"
                return
            }
            var opened = MIDIPortRef()
            let portStatus = MIDIOutputPortCreate(client, "Probe" as CFString, &opened)
            guard portStatus == noErr else {
                failure = "CoreMIDI no arrancó: puerto \(portStatus)"
                return
            }
            port = opened
        }

        deinit {
            if let port { MIDIPortDispose(port) }
            MIDIClientDispose(client)
        }
    }

    private let midi = Port()

    init() {
        failure = midi.failure
        refreshDestinations()
    }

    /// Envía los bytes tal cual, por la API de paquetes clásica.
    ///
    /// **Timestamp cero, que en CoreMIDI significa «ya».** La sonda no programa
    /// nada en el futuro: lo que se está averiguando es si el hardware responde,
    /// no cuándo. Sellar con el reloj del scheduler es FR6 y es de la Fase 4.
    private func send(_ bytes: [UInt8], describedAs description: String) {
        guard let selected else { return }
        guard let port = midi.port else {
            record("Sin puerto: \(failure ?? "CoreMIDI no arrancó")")
            return
        }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, bytes)
        guard packet != nil else {
            record("\(bytes.count) bytes no caben en el paquete")
            return
        }

        let status = MIDISend(port, selected.endpoint, &packetList)
        record("canal \(channel) · " + description + (status == noErr ? "" : " · \(status)"))
    }

    /// Los destinos del sistema.
    ///
    /// Enumera en crudo por la misma razón que el envío: la sonda no depende del
    /// paquete `MIDI` para nada, así que borrarla no deja rastro.
    private static func systemDestinations() -> [Destination] {
        (0..<MIDIGetNumberOfDestinations()).map { index in
            let endpoint = MIDIGetDestination(index)
            var name: Unmanaged<CFString>?
            let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            guard status == noErr, let name else {
                return Destination(endpoint: endpoint, displayName: "Unknown")
            }
            return Destination(
                endpoint: endpoint, displayName: name.takeRetainedValue() as String)
        }
    }

    /// Lee una tira de bytes en hexadecimal, con o sin espacios.
    ///
    /// Devuelve `nil` si algo no es un byte: teclear SysEx a mano es teclear mal
    /// de vez en cuando, y mandar medio mensaje sería peor que no mandar nada.
    static func parseHex(_ text: String) -> [UInt8]? {
        let fields = text.split(whereSeparator: { $0 == " " || $0 == "," })
        guard !fields.isEmpty else { return nil }
        var bytes: [UInt8] = []
        for field in fields {
            guard let byte = UInt8(field, radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }

    func refreshDestinations() {
        destinations = Self.systemDestinations()
        // Si el destino elegido desapareció, se suelta: enviarle a un endpoint
        // muerto no da error —CoreMIDI acepta el mensaje y lo descarta—, así que
        // la sonda parecería estar mandando.
        if let selected, !destinations.contains(selected) {
            self.selected = nil
        }
    }

    func select(_ destination: Destination) { selected = destination }

    func isSelected(_ destination: Destination) -> Bool { selected == destination }

    func sendNoteOn(_ note: Int) {
        guard let note = UInt8(exactly: note), let velocity = UInt8(exactly: velocity) else {
            return
        }
        send([0x90 | wireChannel, note, velocity], describedAs: "note-on \(note) vel \(velocity)")
    }

    func sendNoteOff(_ note: Int) {
        guard let note = UInt8(exactly: note) else { return }
        send([0x80 | wireChannel, note, 0], describedAs: "note-off \(note)")
    }

    /// El canal, 0-indexado, como viaja en el nibble bajo del status.
    private var wireChannel: UInt8 { UInt8(channel - 1) }

    /// Deja el controlador a oscuras sin tener que pulsar dieciséis veces.
    func sweepNotesOff() {
        for note in noteNumbers { sendNoteOff(note) }
    }

    func sendControlChange(_ controller: Int) {
        guard let controller = UInt8(exactly: controller),
            let value = UInt8(exactly: controllerValue)
        else { return }
        send([0xB0 | wireChannel, controller, value], describedAs: "CC \(controller) = \(value)")
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
