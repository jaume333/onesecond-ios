import SwiftUI

/// Idioma de la app: castellano, catalán o inglés (como en Android).
func t(_ es: String, _ ca: String, _ en: String) -> String {
    let l = Locale.preferredLanguages.first?.prefix(2) ?? "es"
    return l == "ca" ? ca : (l == "es" ? es : en)
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
        servidor: nil, esquema: "onesecondgps", gpsDefecto: 1, conPuntos: false)
    static let rider = Prueba(id: "rider", nombre: "Rider 1000",
        sub: ["Seguimiento GPS", "Seguiment GPS", "GPS tracking"],
        metal: [0x2B3038, 0x8D98A8, 0x4B5360],
        patron: "https://(www\\.)?onesecond\\.es/rider1000/api/p/[A-Za-z2-7]{12}/?",
        servidor: "https://onesecond.es/rider1000", esquema: "rider1000gps", gpsDefecto: 60, conPuntos: true)
    static let ronda = Prueba(id: "ronda", nombre: "Ronda la Llana",
        sub: ["Ruta con puntos de control", "Ruta amb punts de control", "Route with checkpoints"],
        metal: [0x3D1E0E, 0xB8693A, 0x6E3519],
        patron: "https://(www\\.)?onesecond\\.es/ronda/api/p/[A-Za-z2-7]{12}/?",
        servidor: "https://onesecond.es/ronda", esquema: "rondagps", gpsDefecto: 60, conPuntos: true)

    static let todas = [rally, rider, ronda]
    static func de(_ id: String) -> Prueba? { todas.first { $0.id == id } }
    static func deQuien(_ url: String) -> Prueba? { todas.first { $0.coincide(url) } }
    static func deEsquema(_ e: String) -> Prueba? { todas.first { $0.esquema == e.lowercased() } }
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
    static let fondo = Color(hex: 0x0E0F12)
    static let panel = Color(hex: 0x1A1C21)
    static let borde = Color(hex: 0x2C2F36)
    static let suave = Color(hex: 0x9AA0AA)
    static let oro = Color(hex: 0xD4AF37)
    static let verde = Color(hex: 0x2ECC71)
    static let rojo = Color(hex: 0xE53935)
    static let naranja = Color(hex: 0xF39C12)
}
