import Engine
import Foundation

/// Escribe el trabajo en curso, sin escribir en cada giro de knob.
///
/// **El problema que resuelve es de ráfagas, no de volumen.** El BeatStep Pro
/// tiene cuarenta y ocho controles y un encoder produce decenas de eventos al
/// girarlo; escribir por evento sería escribir en ráfagas de cientos. Y no es
/// barato: guardar un Bank lleno son ~660 KB y 15,5 ms de serialización, medidos
/// en la Fase 4.
///
/// **Espera a la calma y escribe solo lo que cambió.** Un par de segundos sin
/// tocar nada y se escribe; el Bank tocado y no los dieciséis, que es lo que el
/// reparto de ficheros de FR18 existe para permitir — el Project entero costaría
/// 243,6 ms.
///
/// **El reloj es inyectable, y no por purismo.** Un test que espere dos segundos
/// de verdad es un test que algún día falla solo, en el runner cargado de CI. Se
/// le pregunta la hora a una función; en producción es el reloj del sistema.
///
/// **No tiene temporizador dentro.** Quien lo llama decide cuándo mirar
/// —`tick()`— y eso es lo que lo mantiene probable y lo que evita meter un
/// `Timer` en un paquete que no sabe de ciclos de vida. En la app lo despierta
/// la pantalla.
public final class Autosave: @unchecked Sendable {

    private let store: ProjectStore
    private let quietPeriod: TimeInterval
    private let now: @Sendable () -> TimeInterval

    /// Lo que está esperando a escribirse. **El último cambio de cada Bank
    /// gana**: si un Bank se toca cinco veces antes de la calma, lo que se
    /// escribe es su estado final, no cinco versiones.
    private var pendingBanks: [Int: Bank] = [:]

    /// La cabecera pendiente, si cambió algo de sesión.
    private var pendingHeader: Project?

    /// Cuándo fue el último cambio. La calma se mide desde aquí.
    private var lastChange: TimeInterval?

    public init(
        store: ProjectStore,
        quietPeriod: TimeInterval = 2,
        now: @escaping @Sendable () -> TimeInterval = {
            Date().timeIntervalSinceReferenceDate
        }
    ) {
        self.store = store
        self.quietPeriod = quietPeriod
        self.now = now
    }

    /// Si hay algo esperando a escribirse.
    public var hasPendingWork: Bool { !pendingBanks.isEmpty || pendingHeader != nil }

    /// Cuántos Banks distintos están pendientes.
    public var pendingBankCount: Int { pendingBanks.count }

    /// Un Bank cambió. **No escribe**: anota y reinicia la cuenta de la calma.
    public func changed(_ bank: Bank, at index: Int) {
        pendingBanks[index] = bank
        lastChange = now()
    }

    /// Cambió algo de la cabecera —qué Bank se mira, el reloj, el hardware—.
    public func changedHeader(_ project: Project) {
        pendingHeader = project
        lastChange = now()
    }

    /// Mira si ya toca escribir.
    ///
    /// **No hace nada mientras siga habiendo movimiento**, que es todo el
    /// mecanismo: cada cambio empuja la calma hacia delante, así que un giro
    /// largo de knob produce una escritura al final y no una por vuelta.
    public func tick() throws {
        guard hasPendingWork, let lastChange else { return }
        guard now() - lastChange >= quietPeriod else { return }
        try flush()
    }

    /// Escribe lo pendiente **ahora**, sin esperar a la calma.
    ///
    /// Es lo que llama la app al pasar a segundo plano (FR14): ahí no hay tiempo
    /// de esperar dos segundos, y lo que no se escriba se pierde.
    ///
    /// **Si falla, lo pendiente se conserva.** Un disco lleno no puede además
    /// borrar de memoria lo que no se pudo guardar: el intento siguiente tiene
    /// que poder reintentarlo.
    public func flush() throws {
        var written: [Int] = []
        do {
            for (index, bank) in pendingBanks.sorted(by: { $0.key < $1.key }) {
                try store.save(bank, at: index)
                written.append(index)
            }
            if let pendingHeader {
                try store.saveHeader(of: pendingHeader)
                self.pendingHeader = nil
            }
        } catch {
            for index in written { pendingBanks[index] = nil }
            throw error
        }

        pendingBanks.removeAll()
        lastChange = nil
    }
}
