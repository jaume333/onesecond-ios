import Foundation
import SwiftUI

/// Navigator: las rutas guardadas en el iPhone y las del servidor (https://onesecond.es/mapas/<prueba>/), como
/// Rutas.java de Android. El servidor da la lista de cada carpeta en JSON (autoindex de nginx).
enum Rutas {
    static let servidor = "https://onesecond.es/mapas/"
    static let maxBytes = 30 * 1024 * 1024
    static let orden = ["ronda", "rider1000", "rally", "rallypoker", "pokerrun", "holdemrun"]

    static var carpeta: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("rutas")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func nombrePrueba(_ c: String) -> String {
        switch c {
        case "ronda": return "Ronda la Llana"
        case "rider1000": return "Rider 1000"
        case "rally": return "One Second Rally"
        case "rallypoker": return "Rally Poker"
        case "pokerrun": return "Poker Run"
        case "holdemrun": return "Hold'em Run"
        case "movil": return t("En este móvil", "En aquest mòbil", "On this phone")
        default: return c.isEmpty ? c : c.prefix(1).uppercased() + c.dropFirst().replacingOccurrences(of: "_", with: " ")
        }
    }
    static func iconoPrueba(_ c: String) -> String {
        switch c {
        case "ronda": return "ic_ronda"
        case "rider1000": return "ic_rider"
        case "rally": return "ic_rally"
        case "rallypoker": return "ic_rallypoker"
        case "pokerrun": return "ic_pokerrun"
        case "holdemrun": return "ic_holdemrun"
        default: return "ic_navigator"
        }
    }
    static func colorPrueba(_ c: String) -> Color {
        switch c {
        case "ronda": return Color(hex: 0xB8693A)
        case "rider1000": return Color(hex: 0x6B7584)
        case "rally": return Color(hex: 0xB8963A)
        case "rallypoker": return Color(hex: 0x4A6FC0)
        case "pokerrun": return Color(hex: 0xC8202D)
        case "holdemrun": return Color(hex: 0x2A9A50)
        default: return Color(hex: 0x2F8FA8)
        }
    }
    /// «La_Ronda_2025_CP3-CP4.gpx» → «La Ronda 2025 CP3-CP4»
    static func nombreDeArchivo(_ f: String) -> String {
        var s = f
        if let p = s.lastIndex(of: "."), p > s.startIndex { s = String(s[..<p]) }
        return s.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    }

    struct Guardada: Codable, Identifiable, Equatable {
        var archivo: String, nombre: String, origen: String, carpeta: String, remoto: String
        var km: Double, subida: Double, t: Double
        var id: String { archivo }
        var fichero: URL { Rutas.carpeta.appendingPathComponent(archivo) }
    }

    static var guardadas: [Guardada] {
        guard let d = UserDefaults.standard.data(forKey: "nav_guardadas"), let l = try? JSONDecoder().decode([Guardada].self, from: d) else { return [] }
        return l.filter { FileManager.default.fileExists(atPath: $0.fichero.path) }.sorted { $0.t > $1.t }
    }
    private static func escribir(_ l: [Guardada]) {
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: "nav_guardadas") }
    }
    static func buscar(_ archivo: String) -> Guardada? { guardadas.first { $0.archivo == archivo } }
    static func delServidor(_ carpeta: String, _ remoto: String) -> Guardada? { guardadas.first { $0.carpeta == carpeta && $0.remoto == remoto } }
    static var ultima: Guardada? { UserDefaults.standard.string(forKey: "nav_ultima").flatMap(buscar) }

    static func tocar(_ archivo: String) {
        var l = guardadas
        for i in l.indices where l[i].archivo == archivo { l[i].t = Date().timeIntervalSince1970 }
        escribir(l)
        UserDefaults.standard.set(archivo, forKey: "nav_ultima")
    }
    static func borrar(_ archivo: String) {
        escribir(guardadas.filter { $0.archivo != archivo })
        try? FileManager.default.removeItem(at: carpeta.appendingPathComponent(archivo))
        if UserDefaults.standard.string(forKey: "nav_ultima") == archivo { UserDefaults.standard.removeObject(forKey: "nav_ultima") }
    }

    /// Guarda un GPX (comprobando que es una ruta de verdad) y lo apunta en la lista.
    @discardableResult
    static func guardar(_ datos: Data, nombreArchivo: String?, origen: String, carpetaSrv: String?, remoto: String?) throws -> Guardada {
        let g = try Gpx.leer(datos)
        let base = nombreArchivo ?? ""
        var nombre = !base.isEmpty ? nombreDeArchivo(base) : !g.nombre.isEmpty ? g.nombre : "Ruta"
        if base.isEmpty && !g.nombre.isEmpty { nombre = g.nombre }
        var limpio = nombre.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
        if limpio.count > 60 { limpio = String(limpio.prefix(60)) }
        let archivo = (carpetaSrv ?? "movil") + "_" + limpio + ".gpx"
        var l = guardadas.filter { $0.archivo != archivo }
        try datos.write(to: carpeta.appendingPathComponent(archivo))
        let r = Guardada(archivo: archivo, nombre: nombre, origen: origen, carpeta: carpetaSrv ?? "", remoto: remoto ?? "",
                         km: g.total / 1000, subida: g.conAltura ? g.subidaTotal : -1, t: Date().timeIntervalSince1970)
        l.append(r)
        escribir(l)
        UserDefaults.standard.set(archivo, forKey: "nav_ultima")
        return r
    }
    static func abrir(_ archivo: String) throws -> Gpx { try Gpx.leer(Data(contentsOf: carpeta.appendingPathComponent(archivo))) }

    struct Remota: Identifiable, Hashable {
        let carpeta: String, archivo: String, bytes: Int
        var id: String { carpeta + "/" + archivo }
        var url: String {
            servidor + (carpeta.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? carpeta) + "/" + (archivo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? archivo)
        }
    }

    /// Carpetas del servidor y sus rutas. Se guarda para verla sin cobertura. nil si no hay conexión ni copia.
    static func listaServidor(red: Bool) async -> [String: [Remota]]? {
        let (c, d) = red ? await Red.pedir(servidor) : (-1, Data())
        if c == 200, let dirs = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            var r: [String: [[String: Any]]] = [:]
            var ok = true
            for dd in dirs where dd.str("type") == "directory" {
                let nom = dd.str("name")
                if nom.isEmpty || nom.hasPrefix(".") { continue }
                let (cf, df) = await Red.pedir(servidor + (nom.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nom) + "/")
                guard cf == 200, let fs = try? JSONSerialization.jsonObject(with: df) as? [[String: Any]] else { ok = false; break }
                r[nom] = fs.filter { $0.str("type") == "file" && $0.str("name").lowercased().hasSuffix(".gpx") }
                    .map { ["archivo": $0.str("name"), "bytes": $0.int("size"), "fecha": $0.str("mtime")] }
            }
            if ok, let data = try? JSONSerialization.data(withJSONObject: r) {
                UserDefaults.standard.set(data, forKey: "nav_servidor")
                return convertir(r)
            }
        }
        guard let g = UserDefaults.standard.data(forKey: "nav_servidor"), let r = try? JSONSerialization.jsonObject(with: g) as? [String: [[String: Any]]] else { return nil }
        return convertir(r)
    }
    private static func convertir(_ r: [String: [[String: Any]]]) -> [String: [Remota]] {
        r.mapValues { $0.map { Remota(carpeta: "", archivo: $0.str("archivo"), bytes: $0.int("bytes")) } }
            .reduce(into: [:]) { acc, kv in acc[kv.key] = kv.value.map { Remota(carpeta: kv.key, archivo: $0.archivo, bytes: $0.bytes) } }
    }

    static func bajar(_ url: String) async throws -> Data {
        let (c, d) = await Red.pedir(url)
        guard c == 200 else { throw URLError(.badServerResponse) }
        guard d.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
        return d
    }

    static func km(_ km: Double) -> String { km >= 100 ? String(format: "%.0f", km) : String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",") }
    static func detalle(_ g: Guardada) -> String {
        var s = km(g.km) + " km"
        if g.subida >= 0 { s += " · +" + Poker.miles(Int(g.subida.rounded())) + " m" }
        return s
    }
}
