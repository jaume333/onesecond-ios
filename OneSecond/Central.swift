import Foundation
import CoreLocation
import UIKit

/// El corazón de la app: qué prueba está vinculada, la emisión del GPS y el envío al servidor.
/// Como en Android: solo una prueba vinculada y solo una emitiendo a la vez.
@MainActor
final class Central: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Central()

    @Published var tick = 0                       // para refrescar las pantallas
    @Published private(set) var emitiendo: String? = nil
    @Published var mensajeBreve: (String, Bool)? = nil   // texto, ¿error?

    // estado de la emisión (para la pantalla)
    private(set) var enviadas = 0
    private(set) var sinRed = false
    private(set) var codigoMal = false
    private(set) var ultimaPos: Date? = nil
    private(set) var ultimaPrec: Double = 0
    private(set) var falso = false
    private(set) var autorizacion: CLAuthorizationStatus = .notDetermined

    private let lm = CLLocationManager()
    private var colas: [String: Cola] = [:]
    private var avisosDe: [String: Avisos] = [:]
    private var mensajesDe: [String: Mensajes] = [:]
    private var puntosDe: [String: Puntos] = [:]

    private var timer: Timer?
    private var enviando = false
    private var ultimoEnvio = Date.distantPast
    private var ultimaCola = Date.distantPast
    private var ultimaSincroAvisos = Date.distantPast
    private var ultimaConsultaMsg = Date.distantPast
    private var rafagaHasta = Date.distantPast
    private var enviarYa = false
    private var gpsPunto = Int.max
    private var pvServidor: String? = nil
    private var esperandoPermiso = false

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.distanceFilter = kCLDistanceFilterNone
        lm.activityType = .automotiveNavigation
        lm.pausesLocationUpdatesAutomatically = false
        autorizacion = lm.authorizationStatus
        UIDevice.current.isBatteryMonitoringEnabled = true
        if Demo.activo { cargarDemo(); return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.cadaSegundo() }
        }
        // si la app se cerró emitiendo, se sigue emitiendo al volver a abrirla
        if let id = UserDefaults.standard.string(forKey: "emitiendo"), let p = Prueba.de(id), Ajustes(p: p).vinculada {
            emitir(p)
        }
    }

    // ---------- objetos de cada prueba ----------
    func aj(_ p: Prueba) -> Ajustes { Ajustes(p: p) }
    func cola(_ p: Prueba) -> Cola { if let c = colas[p.id] { return c }; let c = Cola(p.id); colas[p.id] = c; return c }
    func avisos(_ p: Prueba) -> Avisos { if let a = avisosDe[p.id] { return a }; let a = Avisos(aj(p)); avisosDe[p.id] = a; return a }
    func mensajes(_ p: Prueba) -> Mensajes { if let m = mensajesDe[p.id] { return m }; let m = Mensajes(aj(p)); mensajesDe[p.id] = m; return m }
    func puntos(_ p: Prueba) -> Puntos { if let x = puntosDe[p.id] { return x }; let x = Puntos(aj(p)); puntosDe[p.id] = x; return x }

    var vinculada: Prueba? { Prueba.todas.first { aj($0).vinculada } }
    func emitiendo(_ p: Prueba) -> Bool { emitiendo == p.id }
    var ultimaLocalizacion: CLLocation? { lm.location }

    func breve(_ s: String, error: Bool = false) {
        mensajeBreve = (s, error)
        Task { try? await Task.sleep(nanoseconds: 3_500_000_000); if mensajeBreve?.0 == s { mensajeBreve = nil } }
    }

    // ---------- vincular ----------
    /// Guarda la dirección del piloto. Devuelve un error para enseñar, o nil si todo bien.
    func vincular(_ p: Prueba, url: String) -> String? {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let otra = Prueba.deQuien(u), otra.id != p.id {
            return t("Este enlace es de ", "Aquest enllaç és de ", "This link is for ") + otra.nombre + ". " + t("Ábrelo desde esa prueba.", "Obre'l des d'aquesta prova.", "Open it from that event.")
        }
        guard p.coincide(u) else {
            return t("Esa dirección no es de One Second. Pídela a la organización o escanea el QR.", "Aquesta adreça no és de One Second. Demana-la a l'organització o escaneja el QR.", "That address is not a One Second one. Ask the organisers or scan the QR.")
        }
        if let e = emitiendo, e != p.id {
            return t("Pulsa PARAR en ", "Prem ATURAR a ", "Press STOP in ") + (Prueba.de(e)?.nombre ?? "") + t(" antes de vincular otra prueba.", " abans de vincular una altra prova.", " before linking another event.")
        }
        if emitiendo == p.id { return t("Pulsa PARAR antes de cambiar la vinculación.", "Prem ATURAR abans de canviar la vinculació.", "Press STOP before changing the link.") }
        for o in Prueba.todas where o.id != p.id { aj(o).url = "" }   // solo una vinculada
        aj(p).url = u
        aj(p).dorsal = ""; aj(p).nombrePiloto = ""
        Cuenta.shared.marcarVista(u)
        tick += 1
        // el dorsal y el nombre del piloto, para enseñarlos en la pantalla de inicio (GET a su dirección)
        Task {
            let (c, d) = await Red.pedir(u)
            let o = Red.objeto(d)
            if c == 200, !o.str("dorsal").isEmpty, aj(p).url == u {
                aj(p).dorsal = o.str("dorsal"); aj(p).nombrePiloto = o.str("nombre"); tick += 1
            }
        }
        return nil
    }

    /// Rider 1000 y Ronda: vincular con el dorsal y el teléfono de la inscripción.
    func vincularDorsal(_ p: Prueba, dorsal: String, telefono: String) async -> String? {
        guard let srv = p.servidor else { return nil }
        let (c, d) = await Red.pedir(srv + "/api/vincular", cuerpo: ["dorsal": dorsal, "telefono": telefono])
        if c == -1 { return t("Sin conexión. Inténtalo con cobertura.", "Sense connexió. Prova-ho amb cobertura.", "No connection. Try again with coverage.") }
        let r = Red.objeto(d)
        let url = r.str("url")
        if c == 200 && p.coincide(url) {
            if let e = vincular(p, url: url) { return e }
            let tel = r.str("tel_org")
            if !tel.isEmpty { aj(p).telOrg = tel }
            return nil
        }
        let e = r.str("error")
        return e.isEmpty ? t("No se ha encontrado la inscripción con ese dorsal y teléfono.", "No s'ha trobat la inscripció amb aquest dorsal i telèfon.", "No entry found with that number and phone.") : e
    }

    func desvincular(_ p: Prueba) {
        if emitiendo == p.id { return }
        aj(p).url = ""
        aj(p).dorsal = ""; aj(p).nombrePiloto = ""
        tick += 1
    }

    // ---------- emitir ----------
    func emitir(_ p: Prueba) {
        guard aj(p).vinculada else { return }
        if let e = emitiendo, e != p.id { breve(t("Ya se está emitiendo en otra prueba.", "Ja s'està emetent en una altra prova.", "Already sending in another event."), error: true); return }
        Notificar.pedirPermiso()
        switch lm.authorizationStatus {
        case .notDetermined:
            esperandoPermiso = true
            UserDefaults.standard.set(p.id, forKey: "emitiendo_pedido")
            lm.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            breve(t("Sin permiso de ubicación: actívalo en Ajustes › One Second › Ubicación.", "Sense permís d'ubicació: activa'l a Configuració › One Second › Ubicació.", "No location permission: enable it in Settings › One Second › Location."), error: true)
            return
        default: break
        }
        emitiendo = p.id
        UserDefaults.standard.set(p.id, forKey: "emitiendo")
        enviadas = 0; sinRed = false; codigoMal = false
        gpsPunto = Int.max
        if p.conPuntos, let b = aj(p).base { puntos(p).cargarGuardados(b) }
        lm.allowsBackgroundLocationUpdates = true
        lm.showsBackgroundLocationIndicator = true
        ponerPrecision()
        lm.startUpdatingLocation()
        ultimoEnvio = .distantPast
        tick += 1
    }

    func parar() {
        guard let id = emitiendo, let p = Prueba.de(id) else { return }
        lm.stopUpdatingLocation()
        lm.allowsBackgroundLocationUpdates = false
        emitiendo = nil
        UserDefaults.standard.removeObject(forKey: "emitiendo")
        tick += 1
        // se envía lo que quede (los últimos segundos antes de parar)
        Task {
            for _ in 0..<20 {
                let lote = cola(p).primeras(300)
                if lote.isEmpty { break }
                let (c, _) = await Red.pedir(aj(p).url, texto: "[" + lote.joined(separator: ",") + "]")
                if c != 200 { break }
                cola(p).quitar(lote.count)
                enviadas += lote.count
            }
            if p.conPuntos, let b = aj(p).base { await puntos(p).enviarPasos(b) }
            tick += 1
        }
    }

    /// Tras un aviso: 3 minutos de GPS cada segundo y envío cada 10 s, para que la organización vea dónde está.
    func rafaga() { rafagaHasta = Date().addingTimeInterval(180); enviarYa = true; ponerPrecision() }

    func gpsActual(_ p: Prueba) -> Int { gpsAhora(p) }
    private func gpsAhora(_ p: Prueba) -> Int {
        let g = Date() < rafagaHasta ? 1 : aj(p).gpsSeg
        return max(1, min(g, gpsPunto))
    }
    private func cadaAhora(_ p: Prueba) -> Int {
        Date() < rafagaHasta ? min(aj(p).cadaSeg, 10) : aj(p).cadaSeg
    }

    /// Con lecturas muy espaciadas (seguimiento), el GPS no hace falta a máxima precisión: ahorra batería.
    private func ponerPrecision() {
        guard let id = emitiendo, let p = Prueba.de(id) else { return }
        let g = gpsAhora(p)
        lm.desiredAccuracy = g >= 30 ? kCLLocationAccuracyNearestTenMeters : kCLLocationAccuracyBestForNavigation
    }

    // ---------- GPS ----------
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in for l in locations { self.nuevaPosicion(l) } }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.autorizacion = manager.authorizationStatus
            if self.esperandoPermiso, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                self.esperandoPermiso = false
                if let id = UserDefaults.standard.string(forKey: "emitiendo_pedido"), let p = Prueba.de(id) { self.emitir(p) }
            }
            self.tick += 1
        }
    }

    private func nuevaPosicion(_ l: CLLocation) {
        guard let id = emitiendo, let p = Prueba.de(id) else { return }
        if l.horizontalAccuracy < 0 { return }
        var mock = false
        if #available(iOS 15.0, *), let s = l.sourceInformation { mock = s.isSimulatedBySoftware }
        falso = mock
        ultimaPos = Date()
        ultimaPrec = l.horizontalAccuracy
        if p.conPuntos && !mock {
            let r = puntos(p).revisar(l)
            if r.gps != gpsPunto { gpsPunto = r.gps; ponerPrecision() }
            if r.paso { enviarYa = true; Notificar.enviar(titulo: p.nombre, texto: "✓ " + puntos(p).ultimoNombre) }
        }
        // iOS da posiciones cada segundo: se guardan con el intervalo que pide la organización
        if Date().timeIntervalSince(ultimaCola) < Double(gpsAhora(p)) - 0.3 { return }
        ultimaCola = Date()
        let dev = UIDevice.current
        var extra = ""
        if dev.batteryLevel >= 0 {
            let cargando = dev.batteryState == .charging || dev.batteryState == .full
            extra = String(format: ",\"bat\":%d,\"chg\":%d", Int((dev.batteryLevel * 100).rounded()), cargando ? 1 : 0)
        }
        let linea = String(format: "{\"time\":%lld,\"lat\":%.7f,\"lon\":%.7f,\"acc\":%.1f,\"spd\":%.2f,\"mock\":%d%@}",
                           Int64(l.timestamp.timeIntervalSince1970 * 1000), l.coordinate.latitude, l.coordinate.longitude,
                           l.horizontalAccuracy, l.speed >= 0 ? l.speed : -1.0, mock ? 1 : 0, extra)
        cola(p).anadir(linea)
    }

    // ---------- envío ----------
    private func cadaSegundo() {
        tick += 1
        if let id = emitiendo, let p = Prueba.de(id), !enviando {
            let toca = Date().timeIntervalSince(ultimoEnvio) >= Double(cadaAhora(p)) || enviarYa || cola(p).tamano >= 300
            if toca {
                enviando = true
                Task { await ciclo(p); enviando = false }
            } else if cadaAhora(p) > 60 && Date().timeIntervalSince(ultimaConsultaMsg) > 60 {
                ultimaConsultaMsg = Date()
                Task { await mensajes(p).consultar() }
            }
        }
        // avisos: se envían en cuanto hay red y se pregunta por la respuesta de la organización
        if let p = vinculada, avisos(p).hayPendientes, Date().timeIntervalSince(ultimaSincroAvisos) > 20 {
            ultimaSincroAvisos = Date()
            Task { await avisos(p).sincronizar(); tick += 1 }
        }
    }

    private func ciclo(_ p: Prueba) async {
        enviarYa = false
        ultimoEnvio = Date()
        guard let base = aj(p).base else { return }
        if p.conPuntos {
            await puntos(p).enviarPasos(base)
            if puntos(p).hayQueDescargar(pvServidor) { await puntos(p).descargar(base) }
        }
        var vueltas = 0
        repeat {
            let lote = cola(p).primeras(300)
            if lote.isEmpty { break }
            let (c, d) = await Red.pedir(aj(p).url, texto: "[" + lote.joined(separator: ",") + "]")
            if c == 200 {
                cola(p).quitar(lote.count)
                enviadas += lote.count
                sinRed = false; codigoMal = false
                let j = Red.objeto(d)
                let a = aj(p)
                a.cadaSeg = max(5, min(900, j.int("cada", 15)))
                a.gpsSeg = max(1, min(900, j.int("gps", p.gpsDefecto)))
                if j["pv"] != nil { pvServidor = j.str("pv") }
                ponerPrecision()
                await mensajes(p).llegados(j["msgs"] as? [[String: Any]])
            } else if c == 404 {
                codigoMal = true; break
            } else {
                sinRed = true; break
            }
            vueltas += 1
        } while cola(p).tamano >= 300 && vueltas < 10
        tick += 1
    }

    /// Capturas de la App Store: Ronda la Llana vinculada y emitiendo, con puntos, mensajes y un aviso de ejemplo.
    private func cargarDemo() {
        let p = Demo.pantalla == 12 ? Prueba.rider : Prueba.ronda
        for o in Prueba.todas { aj(o).url = "" }
        aj(p).url = p.id == "rider" ? "https://onesecond.es/rider1000/api/p/ABCDEFGH2345" : "https://onesecond.es/ronda/api/p/ABCDEFGH2345"
        aj(p).telOrg = "+34 600 000 000"
        aj(p).dorsal = "27"; aj(p).nombrePiloto = "Jaume Garcia"
        if Demo.pantalla != 5 && Demo.pantalla != 12 { emitiendo = p.id }
        enviadas = 1287; ultimaPos = Date(); ultimaPrec = 4
        puntos(p).cargarDemo(); mensajes(p).cargarDemo(); avisos(p).cargarDemo()
    }

    var pendientes: Int { emitiendo.flatMap { Prueba.de($0) }.map { cola($0).tamano } ?? 0 }
}
