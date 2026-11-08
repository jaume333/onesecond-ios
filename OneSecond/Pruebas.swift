import SwiftUI

/// Idioma de la app: castellano, catalán o inglés (como en Android). Las banderitas de la pantalla de inicio
/// lo cambian y se recuerda; si no se ha elegido, el del iPhone.
enum Idioma {
    static var elegido: Int {
        get { UserDefaults.standard.object(forKey: "idioma") as? Int ?? -1 }
        set { UserDefaults.standard.set(newValue, forKey: "idioma") }
    }
    static var actual: Int {
        if elegido >= 0 { return elegido }
        let l = Locale.preferredLanguages.first?.prefix(2) ?? "es"
        return l == "ca" ? 1 : (l == "es" ? 0 : 2)
    }
    static var codigo: String { ["es", "ca", "en"][actual] }
    static var locale: Locale { Locale(identifier: ["es_ES", "ca_ES", "en_GB"][actual]) }
}

func t(_ es: String, _ ca: String, _ en: String) -> String {
    switch Idioma.actual { case 1: return ca; case 2: return en; default: return es }
}

/// Cada prueba es independiente (sus ajustes, su emisión, sus mensajes y sus avisos), pero solo una vinculada
/// y solo una emitiendo a la vez.
struct Prueba: Identifiable, Hashable {
    let id: String
    let nombre: String
    let sub: [String]           // es, ca, en
    let metal: [UInt32]         // oscuro, claro, medio
    let patron: String
    let servidor: String?       // para vincular con dorsal y teléfono (Rider 1000, Ronda)
    let esquema: String
    let gpsDefecto: Int
    let conPuntos: Bool
    let icono: String
    /// El nombre de la prueba en los eventos de las cuentas (rally, rider1000, ronda).
    var appCuentas: String { id == "rider" ? "rider1000" : id }

    var subtitulo: String { t(sub[0], sub[1], sub[2]) }
    var oscuro: Color { Color(hex: metal[0]) }
    var claro: Color { Color(hex: metal[1]) }
    var medio: Color { Color(hex: metal[2]) }

    func coincide(_ url: String) -> Bool {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let re = try? NSRegularExpression(pattern: "^" + patron + "$") else { return false }
        return re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)) != nil
    }

    static let rally = Prueba(id: "rally", nombre: "One Second Rally",
        sub: ["Rally y Rally Poker", "Ral·li i Rally Poker", "Rally and Rally Poker"],
        metal: [0x4A3A10, 0xC9A646, 0x8A6D1F],
        patron: "https://(www\\.)?onesecond\\.es(?!/(rider1000|ronda)/)(/[A-Za-z0-9_.-]+)*/api/p/[A-Za-z2-7]{12}/?",
        servidor: nil, esquema: "onesecondgps", gpsDefecto: 1, conPuntos: false, icono: "ic_rally")
    static let rider = Prueba(id: "rider", nombre: "Rider 1000",
        sub: ["Seguimiento GPS", "Seguiment GPS", "GPS tracking"],
        metal: [0x2B3038, 0x8D98A8, 0x4B5360],
        patron: "https://(www\\.)?onesecond\\.es/rider1000/api/p/[A-Za-z2-7]{12}/?",
        servidor: "https://onesecond.es/rider1000", esquema: "rider1000gps", gpsDefecto: 60, conPuntos: true, icono: "ic_rider")
    static let ronda = Prueba(id: "ronda", nombre: "Ronda la Llana",
        sub: ["Descubrir, Coleccionar, Compartir", "Descobrir, Col·leccionar, Compartir", "Discover, Collect, Share"],
        metal: [0x3D1E0E, 0xB8693A, 0x6E3519],
        patron: "https://(www\\.)?onesecond\\.es/ronda/api/p/[A-Za-z2-7]{12}/?",
        servidor: "https://onesecond.es/ronda", esquema: "rondagps", gpsDefecto: 60, conPuntos: true, icono: "ic_ronda")

    static let todas = [rally, rider, ronda]
    static func de(_ id: String) -> Prueba? { todas.first { $0.id == id } }
    static func deQuien(_ url: String) -> Prueba? { todas.first { $0.coincide(url) } }
    static func deEsquema(_ e: String) -> Prueba? { todas.first { $0.esquema == e.lowercased() } }
    static func deCuentas(_ app: String) -> Prueba? { todas.first { $0.appCuentas == app } }
}

/// Pruebas sin seguimiento GPS en la app (Rally Poker, Poker Run, Hold'em Run): inscribirse, pagar y ver el resultado.
struct PruebaWeb: Identifiable, Hashable {
    let id: String          // nombre en las cuentas: rallypoker, pokerrun, holdemrun
    let nombre: String
    let sub: [String]
    let icono: String
    let metal: [UInt32]
    let web: String
    var subtitulo: String { t(sub[0], sub[1], sub[2]) }

    static let todas = [
        PruebaWeb(id: "rallypoker", nombre: "One Second Rally Poker", sub: ["Regularidad y póker", "Regularitat i pòquer", "Regularity and poker"],
                  icono: "ic_rallypoker", metal: [0x14223A, 0x4A78C2, 0x8E1622], web: "/rallypoker/"),
        PruebaWeb(id: "pokerrun", nombre: "Poker Run", sub: ["Una carta en cada punto", "Una carta a cada punt", "One card at each checkpoint"],
                  icono: "ic_pokerrun", metal: [0x3A0D12, 0xC8202D, 0x8A6D1F], web: "/poker-run/"),
        PruebaWeb(id: "holdemrun", nombre: "Hold'em Run", sub: ["Dos cartas en cada punto", "Dues cartes a cada punt", "Two cards at each checkpoint"],
                  icono: "ic_holdemrun", metal: [0x0B2A1A, 0x1F8A4C, 0x8A6D1F], web: "/holdemrun/"),
    ]
}

/// Ajustes guardados de cada prueba (UserDefaults con el id de la prueba delante).
struct Ajustes {
    let p: Prueba
    private var d: UserDefaults { .standard }
    private func k(_ s: String) -> String { p.id + "_" + s }

    var url: String {
        get { d.string(forKey: k("url")) ?? "" }
        nonmutating set { d.set(newValue, forKey: k("url")) }
    }
    var telOrg: String {
        get { d.string(forKey: k("tel_org")) ?? "" }
        nonmutating set { d.set(newValue, forKey: k("tel_org")) }
    }
    var cadaSeg: Int {
        get { let v = d.integer(forKey: k("cada_seg")); return v > 0 ? v : 15 }
        nonmutating set { d.set(newValue, forKey: k("cada_seg")) }
    }
    var gpsSeg: Int {
        get { let v = d.integer(forKey: k("gps_seg")); return v > 0 ? v : p.gpsDefecto }
        nonmutating set { d.set(newValue, forKey: k("gps_seg")) }
    }
    var dorsal: String {
        get { d.string(forKey: k("dorsal")) ?? "" }
        nonmutating set { d.set(newValue, forKey: k("dorsal")) }
    }
    var nombrePiloto: String {
        get { d.string(forKey: k("nombre")) ?? "" }
        nonmutating set { d.set(newValue, forKey: k("nombre")) }
    }
    /// «Dorsal 12 · Nombre» del piloto vinculado (o el subtítulo de la prueba si aún no se sabe).
    var piloto: String {
        if dorsal.isEmpty && nombrePiloto.isEmpty { return p.subtitulo }
        if dorsal.isEmpty { return nombrePiloto }
        return t("Dorsal ", "Dorsal ", "No. ") + dorsal + (nombrePiloto.isEmpty ? "" : " · " + nombrePiloto)
    }
    var vinculada: Bool { !url.isEmpty && p.coincide(url) }
    /// Dirección del piloto sin la barra final.
    var base: String? { vinculada ? url.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/$", with: "", options: .regularExpression) : nil }

    func json(_ clave: String) -> Any? {
        guard let s = d.string(forKey: k(clave)), let data = s.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    func guardarJson(_ clave: String, _ v: Any) {
        if let data = try? JSONSerialization.data(withJSONObject: v), let s = String(data: data, encoding: .utf8) { d.set(s, forKey: k(clave)) }
    }
    func borrar(_ clave: String) { d.removeObject(forKey: k(clave)) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static let fondo = Color(hex: 0x07090D)
    static let panel = Color(hex: 0x121822)
    static let borde = Color(hex: 0x253042)
    static let suave = Color(hex: 0x8D9BB0)
    static let texto = Color(hex: 0xE9EEF5)
    static let azul = Color(hex: 0x4A90E2)
    static let oroCuenta = Color(hex: 0xD4A72C)
    static let oro = Color(hex: 0xD4AF37)
    static let verde = Color(hex: 0x3DFF8A)
    static let rojo = Color(hex: 0xFF3B3B)
    static let naranja = Color(hex: 0xF39C12)
}

/// Modo demostración: solo para sacar las capturas de la App Store en el simulador (argumentos -demo -pantalla N).
/// Datos de ejemplo, sin GPS ni servidor. Nunca se activa en un iPhone normal.
enum Demo {
    static let args = ProcessInfo.processInfo.arguments
    static var activo: Bool { args.contains("-demo") }
    static var pantalla: Int {
        if let i = args.firstIndex(of: "-pantalla"), i + 1 < args.count { return Int(args[i + 1]) ?? 1 }
        return 1
    }
}
