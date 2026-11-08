import Foundation
import UserNotifications

/// Cuenta One Second (el mismo correo y contraseña de onesecond.es/cuenta), como en Android 1.14+:
/// entrar, ver «Mis inscripciones» y vincular la app sola con la dirección de piloto de la inscripción (gps_app).
/// También los eventos (/api/eventos): inscripciones abiertas, la próxima Ronda y los avisos de las pruebas.
@MainActor
final class Cuenta: ObservableObject {
    static let shared = Cuenta()
    static let base = "https://onesecond.es/cuenta"
    static let cookie = "os_sesion"

    @Published private(set) var token: String = UserDefaults.standard.string(forKey: "cuenta_token") ?? ""
    @Published private(set) var email: String = UserDefaults.standard.string(forKey: "cuenta_email") ?? ""
    @Published private(set) var eventos: [[String: Any]] = []
    @Published private(set) var abiertas: Set<String> = Set((UserDefaults.standard.string(forKey: "abiertas") ?? "").split(separator: ",").map(String.init))
    @Published var avisosActivos: Bool = UserDefaults.standard.object(forKey: "avisos_pruebas") as? Bool ?? true {
        didSet { UserDefaults.standard.set(avisosActivos, forKey: "avisos_pruebas"); programarAvisos() }
    }
    private(set) var inscritas: Set<Int> = []
    func marcarInscrita(_ id: Int) { inscritas.insert(id); programarAvisos() }
    private var ultimaAuto = Date.distantPast

    var conectado: Bool { !token.isEmpty }

    init() {
        if let d = UserDefaults.standard.data(forKey: "eventos"), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] { eventos = a }
    }

    struct Resp { var codigo = -1; var data = Data(); var token: String? = nil
        var json: [String: Any] { Red.objeto(data) } }

    static func pedir(_ metodo: String, _ ruta: String, cuerpo: [String: Any]? = nil, token: String? = nil) async -> Resp {
        guard let u = URL(string: base + ruta) else { return Resp() }
        var r = URLRequest(url: u)
        r.httpMethod = metodo
        r.httpShouldHandleCookies = false
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("1", forHTTPHeaderField: "X-OneSecond")          // el servidor de cuentas lo pide en POST/PUT/DELETE
        if let tk = token, !tk.isEmpty { r.setValue("\(cookie)=\(tk)", forHTTPHeaderField: "Cookie") }
        if let c = cuerpo {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: c)
        }
        var res = Resp()
        do {
            let (d, resp) = try await Red.sesion.data(for: r)
            guard let h = resp as? HTTPURLResponse else { return res }
            res.codigo = h.statusCode
            res.data = d
            if let sc = h.value(forHTTPHeaderField: "Set-Cookie") {
                for parte in sc.components(separatedBy: ",") {
                    let p = parte.trimmingCharacters(in: .whitespaces)
                    if p.hasPrefix(cookie + "=") {
                        res.token = String(p.dropFirst(cookie.count + 1).split(separator: ";").first ?? "")
                    }
                }
            }
        } catch { res.codigo = -1 }
        return res
    }

    private func guardar(token tk: String, email em: String) {
        token = tk; email = em
        UserDefaults.standard.set(tk, forKey: "cuenta_token")
        UserDefaults.standard.set(em, forKey: "cuenta_email")
    }

    /// Después de entrar con Google o Apple.
    func entrarConToken(_ tk: String, email em: String) { guardar(token: tk, email: em) }

    /// Devuelve nil si ha entrado, o el error para enseñar.
    func entrar(email em: String, clave: String) async -> String? {
        let r = await Cuenta.pedir("POST", "/api/entrar", cuerpo: ["email": em, "clave": clave])
        if r.codigo == 200, let tk = r.token, !tk.isEmpty {
            guardar(token: tk, email: em)
            await actualizar()
            return nil
        }
        if r.codigo == -1 { return t("Sin conexión. Comprueba los datos móviles o el wifi.", "Sense connexió. Comprova les dades mòbils o el wifi.", "No connection. Check mobile data or wifi.") }
        if r.json.str("codigo") == "demasiados_intentos" { return t("Demasiados intentos. Espera unos minutos.", "Massa intents. Espera uns minuts.", "Too many attempts. Wait a few minutes.") }
        return t("Correo o contraseña incorrectos.", "Correu o contrasenya incorrectes.", "Wrong email or password.")
    }

    func salir() {
        let tk = token
        guardar(token: "", email: "")
        inscritas = []
        if !tk.isEmpty { Task { _ = await Cuenta.pedir("POST", "/api/salir", cuerpo: [:], token: tk) } }
        programarAvisos()
    }

    // ---------- inscripciones ----------
    struct Insc: Identifiable { let id = UUID(); let url: String; let prueba: Prueba; let evento: String; let fecha: String; let dorsal: String }

    /// Inscripciones con dirección para la app (pagadas, de hoy en adelante). nil = error de conexión.
    func misInscripciones() async -> [Insc]? {
        guard conectado else { return [] }
        let r = await Cuenta.pedir("GET", "/api/mis_inscripciones", token: token)
        if r.codigo == 401 { guardar(token: "", email: ""); return [] }
        guard r.codigo == 200 else { return nil }
        let a = r.json["inscripciones"] as? [[String: Any]] ?? []
        inscritas = Set(a.filter { ["pagada", "pendiente"].contains($0.str("estado")) && $0.str("tipo") != "aficionado" }.map { $0.int("evento_id") })
        return a.compactMap { o in
            let u = o.str("gps_app").trimmingCharacters(in: .whitespaces)
            guard !u.isEmpty, u != "null", let p = Prueba.deQuien(u) else { return nil }
            let ev = o["evento"] as? [String: Any]
            let d = o.str("dorsal_txt").isEmpty ? o.str("dorsal") : o.str("dorsal_txt")
            return Insc(url: u, prueba: p, evento: ev?.str("nombre") ?? p.nombre, fecha: ev?.str("fecha") ?? "", dorsal: d)
        }
    }

    private var vistas: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "cuenta_vistas") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "cuenta_vistas") }
    }
    func marcarVista(_ url: String) { vistas.insert(url) }

    /// Al abrir la app: si hay una inscripción NUEVA con app, la devuelve para vincularla (como Android 1.15).
    func nuevasParaVincular(_ central: Central) async -> [Insc] {
        guard conectado, Date().timeIntervalSince(ultimaAuto) > 60, central.emitiendo == nil else { return [] }
        ultimaAuto = Date()
        guard let l = await misInscripciones() else { return [] }
        var nuevas: [Insc] = []
        for x in l where !vistas.contains(x.url) {
            if x.url == central.aj(x.prueba).url.trimmingCharacters(in: .whitespaces) { marcarVista(x.url); continue }
            nuevas.append(x)
        }
        return nuevas
    }

    // ---------- eventos ----------
    func actualizar() async {
        let r = await Cuenta.pedir("GET", "/api/eventos")
        if r.codigo == 200, let evs = r.json["eventos"] as? [[String: Any]] {
            let ab = Set(evs.filter { $0.bool("abierto") && !$0.bool("completo") }.map { $0.str("app") })
            abiertas = ab
            UserDefaults.standard.set(ab.sorted().joined(separator: ","), forKey: "abiertas")
            // telemetría gratuita de las pruebas con app (para la próxima Ronda y los avisos)
            let tel = evs.filter { Prueba.deCuentas($0.str("app")) != nil && $0.int("precio_cent", 1) == 0
                && $0.str("fecha").range(of: #"^\d{4}-\d\d-\d\d"#, options: .regularExpression) != nil }
            eventos = tel
            if let d = try? JSONSerialization.data(withJSONObject: tel) { UserDefaults.standard.set(d, forKey: "eventos") }
        }
        if conectado { _ = await misInscripciones() }
        programarAvisos()
    }

    static let madrid = TimeZone(identifier: "Europe/Madrid")!

    /// Hora de salida del evento: su fecha y su hora (si no tiene hora, las 08:00), en hora de Madrid.
    static func salida(_ ev: [String: Any]) -> Date? {
        let f = ev.str("fecha"), hh = ev.str("hora")
        guard f.count >= 10, let y = Int(f.prefix(4)), let m = Int(f.dropFirst(5).prefix(2)), let d = Int(f.dropFirst(8).prefix(2)) else { return nil }
        var c = DateComponents(timeZone: madrid, year: y, month: m, day: d, hour: 8, minute: 0)
        let p = hh.split(separator: ":")
        if p.count >= 2, let h = Int(p[0]), let mi = Int(p[1].prefix(2)) { c.hour = h; c.minute = mi }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = madrid
        return cal.date(from: c)
    }

    static func nombre(_ ev: [String: Any]) -> String {
        let n = Idioma.actual == 1 ? ev.str("nombre_ca") : Idioma.actual == 2 ? ev.str("nombre_en") : ""
        return n.isEmpty || n == "null" ? ev.str("nombre") : n
    }
    static func lugar(_ ev: [String: Any]) -> String { let l = ev.str("lugar"); return l == "null" ? "" : l }

    /// «Sábado 7 de noviembre · Sabadell» de la próxima Ronda (o nil si no se sabe).
    var proximaRonda: String? {
        let ahora = Date()
        var mejor: (Date, [String: Any])? = nil
        for e in eventos where Prueba.deCuentas(e.str("app"))?.id == "ronda" {
            guard let s = Cuenta.salida(e), s > ahora.addingTimeInterval(-12 * 3600) else { continue }
            if mejor == nil || s < mejor!.0 { mejor = (s, e) }
        }
        guard let (s, e) = mejor else { return nil }
        let f = DateFormatter()
        f.locale = Idioma.locale
        f.timeZone = Cuenta.madrid
        f.dateFormat = Idioma.actual == 0 ? "EEEE d 'de' MMMM" : "EEEE d MMMM"
        var d = f.string(from: s)
        d = d.prefix(1).uppercased() + d.dropFirst()
        let l = Cuenta.lugar(e)
        return d + (l.isEmpty ? "" : " · " + l)
    }

    /// Avisos de las pruebas: 3 días y 1 día antes (19:00) si aún puedes inscribirte en la telemetría gratuita,
    /// y la mañana de la prueba.
    func programarAvisos() {
        let c = UNUserNotificationCenter.current()
        c.getPendingNotificationRequests { reqs in
            c.removePendingNotificationRequests(withIdentifiers: reqs.map(\.identifier).filter { $0.hasPrefix("tel_") })
        }
        guard avisosActivos else { return }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = Cuenta.madrid
        let ahora = Date()
        for ev in eventos {
            guard let s = Cuenta.salida(ev) else { continue }
            let id = ev.int("id"), n = Cuenta.nombre(ev), l = Cuenta.lugar(ev)
            let dentro = inscritas.contains(id)
            let puede = ev.bool("abierto") && !ev.bool("completo")
            let hf = DateFormatter(); hf.timeZone = Cuenta.madrid; hf.dateFormat = "HH:mm"
            let hora = hf.string(from: s)
            let df = DateFormatter(); df.locale = Idioma.locale; df.timeZone = Cuenta.madrid; df.dateFormat = "EEEE d"
            for tipo in [3, 1, 0] {
                var cuando: Date
                if tipo == 0 {
                    var k = cal.dateComponents([.year, .month, .day], from: s); k.hour = 6; k.minute = 0
                    let seis = cal.date(from: k) ?? s
                    cuando = max(s.addingTimeInterval(-2 * 3600), min(seis, s.addingTimeInterval(-15 * 60)))
                } else {
                    var k = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: -tipo, to: s) ?? s); k.hour = 19; k.minute = 0
                    cuando = cal.date(from: k) ?? s
                }
                guard cuando > ahora else { continue }
                let tit: String, txt: String
                let lug = l.isEmpty ? "" : t(" en ", " a ", " in ") + l
                if tipo == 0 && dentro {
                    tit = t("🏁 Hoy: ", "🏁 Avui: ", "🏁 Today: ") + n
                    txt = t("Salida a las ", "Sortida a les ", "Start at ") + hora + lug + ". "
                        + t("Abre la app y pulsa EMITIR para enviar tu posición a la organización.", "Obre l'app i prem EMETRE per enviar la teva posició a l'organització.", "Open the app and tap START to share your position with the organisers.")
                } else if !dentro && puede {
                    tit = (tipo == 0 ? t("🏁 Hoy: ", "🏁 Avui: ", "🏁 Today: ") : "📍 ") + n
                    let sal = t("Salida", "Sortida", "Start") + (tipo == 0 ? "" : " " + df.string(from: s)) + t(" a las ", " a les ", " at ") + hora + lug + "."
                    txt = sal + " " + t("Aún puedes inscribirte en la telemetría: es gratis.", "Encara et pots inscriure a la telemetria: és gratuït.", "You can still sign up for the telemetry: it's free.")
                } else { continue }
                let co = UNMutableNotificationContent(); co.title = tit; co.body = txt; co.sound = .default
                co.userInfo = ["evento": id, "inscribir": !dentro && puede, "app": ev.str("app")]
                let comp = cal.dateComponents([.year, .month, .day, .hour, .minute], from: cuando)
                c.add(UNNotificationRequest(identifier: "tel_\(id)_\(tipo)", content: co, trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)))
            }
        }
    }
}
