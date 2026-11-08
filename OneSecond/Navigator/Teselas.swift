import Foundation
import WebKit

/// Estilos del mapa (botón «Mapa»), como Estilos.java de Android. Todos gratuitos:
///  - Oscuro y Claro: OpenStreetMap.
///  - Satélite: fotos aéreas del PNOA (IGN), toda España.
///  - Topográfico: en Cataluña el del ICGC; fuera, el MTN del IGN.
///  - Relieve: relieve sombreado del IGN (IDEE) con el mapa del IGN sin fondo encima.
///  - Híbrido: en Cataluña la ortofoto híbrida del ICGC; fuera, el satélite del IGN con sus nombres encima.
///  - 3D y primera persona: satélite con el relieve real (necesitan cobertura).
enum Estilos {
    static let todos = ["oscuro", "claro", "satelite", "topo", "relieve", "hibrido", "3d", "fp"]
    static func es3d(_ e: String) -> Bool { e == "3d" || e == "fp" }
    static func esOsm(_ e: String) -> Bool { e == "oscuro" || e == "claro" }

    static func nombre(_ e: String) -> String {
        switch e {
        case "claro": return t("Claro", "Clar", "Light")
        case "satelite": return t("Satélite", "Satèl·lit", "Satellite")
        case "topo": return t("Topográfico", "Topogràfic", "Topographic")
        case "relieve": return t("Relieve", "Relleu", "Relief")
        case "hibrido": return t("Híbrido", "Híbrid", "Hybrid")
        case "3d": return "3D"
        case "fp": return t("1ª persona", "1a persona", "First person")
        default: return t("Oscuro", "Fosc", "Dark")
        }
    }
    static func detalle(_ e: String) -> String {
        switch e {
        case "claro": return t("a pleno sol", "a ple sol", "for bright sun")
        case "satelite": return t("fotos aéreas", "fotos aèries", "aerial photos")
        case "topo": return t("curvas de nivel", "corbes de nivell", "contour lines")
        case "relieve": return t("montañas y pistas", "muntanyes i pistes", "hills and tracks")
        case "hibrido": return t("satélite y nombres", "satèl·lit i noms", "satellite + names")
        case "3d": return t("relieve inclinado", "relleu inclinat", "tilted terrain")
        case "fp": return t("detrás de la moto", "darrere la moto", "behind the bike")
        default: return t("de noche", "de nit", "for night")
        }
    }
    static func icono(_ e: String) -> String {
        switch e {
        case "satelite", "hibrido": return "🛰"
        case "topo", "3d": return "⛰"
        case "relieve": return "🏔"
        case "fp": return "👁"
        case "claro": return "☀"
        default: return "☾"
        }
    }
    static func miniatura(_ e: String) -> String { "nav_estilo_" + (e == "3d" ? "3d" : e == "fp" ? "fp" : e) }
    static func credito(_ e: String, _ cat: Bool) -> String {
        switch e {
        case "satelite": return "PNOA cedido por © IGN"
        case "3d", "fp": return "PNOA cedido por © IGN · relieve: Terrain Tiles"
        case "topo": return cat ? "© Institut Cartogràfic i Geològic de Catalunya" : "© Instituto Geográfico Nacional"
        case "relieve": return "© Instituto Geográfico Nacional"
        case "hibrido": return cat ? "© Institut Cartogràfic i Geològic de Catalunya" : "PNOA cedido por © IGN · © IGN"
        default: return "© OpenStreetMap"
        }
    }
    /// Las capas (claves de Teselas) que usa cada estilo, para guardarlas.
    static func capas(_ e: String, _ cat: Bool) -> [String] {
        switch e {
        case "satelite": return ["pnoa"]
        case "topo": return [cat ? "icgctopo" : "mtn"]
        case "relieve": return ["relieve", "ignbase"]
        case "hibrido": return cat ? ["icgchibrida"] : ["pnoa", "ignnombres"]
        case "3d", "fp": return ["pnoa", "ignnombres", "dem"]
        default: return ["osm"]
        }
    }
    /// ¿La ruta está en Cataluña? (el centro de la ruta dentro del rectángulo de Cataluña)
    static func enCatalunya(_ g: Gpx) -> Bool {
        var la = 0.0, lo = 0.0, c = 0.0
        let paso = max(1, g.n / 200)
        for i in stride(from: 0, to: g.n, by: paso) { la += g.lat[i]; lo += g.lon[i]; c += 1 }
        la /= c; lo /= c
        return la > 40.52 && la < 42.86 && lo > 0.16 && lo < 3.33
    }
}

/// Las teselas del mapa: el mapa las pide con tesela://t/<capa>/z/x/y y aquí se sirven del iPhone si están guardadas,
/// o se bajan del servidor (y se guardan). Así el mapa guardado de una ruta se ve sin cobertura.
final class Teselas: NSObject, WKURLSchemeHandler {
    static let shared = Teselas()

    private static let ign = "https://www.ign.es/wmts/"
    private static func wmtsIgn(_ servicio: String, _ capa: String, _ formato: String) -> String {
        ign + servicio + "?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=" + capa + "&STYLE=default&FORMAT=" + formato
            + "&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}"
    }
    private static let icgc = "https://geoserveis.icgc.cat/servei/catalunya/mapa-base/wmts/"
    static let plantillas: [String: String] = [
        "osm": "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        "pnoa": wmtsIgn("pnoa-ma", "OI.OrthoimageCoverage", "image/jpeg"),
        "mtn": wmtsIgn("mapa-raster", "MTN", "image/jpeg"),
        "ignnombres": wmtsIgn("ign-base", "IGNBaseOrto", "image/png"),
        "ignbase": wmtsIgn("ign-base", "IGNBaseTodo-nofondo", "image/png"),
        "relieve": "https://servicios.idee.es/wmts/mdt?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=Relieve&STYLE=Default&FORMAT=image/jpeg&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}",
        "icgctopo": icgc + "topografic/MON3857NW/{z}/{x}/{y}.png",
        "icgchibrida": icgc + "orto-hibrida/MON3857NW/{z}/{x}/{y}.png",
        "dem": "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png",
    ]

    private let sesion: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpMaximumConnectionsPerHost = 6
        c.httpAdditionalHeaders = ["User-Agent": "OneSecond/1.57 (iPhone; https://onesecond.es)"]
        c.urlCache = nil
        return URLSession(configuration: c)
    }()
    private var vivas = Set<ObjectIdentifier>()
    private let cerrojo = NSLock()

    static var carpeta: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("teselas")
    }
    /// Las teselas guardadas a propósito para una ruta van aparte (no las borra el sistema al limpiar cachés).
    static var guardadas: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("teselas")
    }
    static func ruta(_ base: URL, _ k: String, _ z: Int, _ x: Int, _ y: Int) -> URL {
        base.appendingPathComponent("\(k)/\(z)/\(x)/\(y)")
    }
    static func local(_ k: String, _ z: Int, _ x: Int, _ y: Int) -> URL? {
        for b in [guardadas, carpeta] {
            let u = ruta(b, k, z, x, y)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
    static func url(_ k: String, _ z: Int, _ x: Int, _ y: Int) -> URL? {
        guard let p = plantillas[k] else { return nil }
        return URL(string: p.replacingOccurrences(of: "{z}", with: "\(z)").replacingOccurrences(of: "{x}", with: "\(x)").replacingOccurrences(of: "{y}", with: "\(y)"))
    }
    private static func tipo(_ d: Data) -> String { d.starts(with: [0x89, 0x50]) ? "image/png" : "image/jpeg" }

    func webView(_ webView: WKWebView, start t: WKURLSchemeTask) {
        let id = ObjectIdentifier(t)
        cerrojo.lock(); vivas.insert(id); cerrojo.unlock()
        let p = t.request.url?.pathComponents.filter { $0 != "/" } ?? []        // [capa, z, x, y]
        guard p.count == 4, let z = Int(p[1]), let x = Int(p[2]), let y = Int(p[3]) else { fallo(t, id); return }
        let k = p[0]
        if let u = Teselas.local(k, z, x, y), let d = try? Data(contentsOf: u) { servir(t, id, d); return }
        guard let remoto = Teselas.url(k, z, x, y) else { fallo(t, id); return }
        sesion.dataTask(with: remoto) { [weak self] d, r, _ in
            guard let self = self else { return }
            if let d = d, (r as? HTTPURLResponse)?.statusCode == 200, !d.isEmpty {
                let dest = Teselas.ruta(Teselas.carpeta, k, z, x, y)
                try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? d.write(to: dest)
                DispatchQueue.main.async { self.servir(t, id, d) }
            } else {
                DispatchQueue.main.async { self.fallo(t, id) }
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, stop t: WKURLSchemeTask) {
        cerrojo.lock(); vivas.remove(ObjectIdentifier(t)); cerrojo.unlock()
    }

    private func viva(_ id: ObjectIdentifier) -> Bool { cerrojo.lock(); defer { cerrojo.unlock() }; return vivas.contains(id) }
    private func acabar(_ id: ObjectIdentifier) { cerrojo.lock(); vivas.remove(id); cerrojo.unlock() }

    private func servir(_ t: WKURLSchemeTask, _ id: ObjectIdentifier, _ d: Data) {
        guard viva(id), let u = t.request.url else { return }
        acabar(id)
        t.didReceive(HTTPURLResponse(url: u, statusCode: 200, httpVersion: "HTTP/1.1",
                                     headerFields: ["Content-Type": Teselas.tipo(d), "Access-Control-Allow-Origin": "*"])!)
        t.didReceive(d)
        t.didFinish()
    }
    private func fallo(_ t: WKURLSchemeTask, _ id: ObjectIdentifier) {
        guard viva(id), let u = t.request.url else { return }
        acabar(id)
        t.didReceive(HTTPURLResponse(url: u, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"])!)
        t.didFinish()
    }

    // ---------- guardar el mapa de una ruta ----------
    /// Las teselas que tocan la ruta (con las de al lado si la ruta pasa cerca del borde), de zMin a zMax.
    static func pasillo(_ g: Gpx, _ zMin: Int, _ zMax: Int) -> [(Int, Int, Int)] {
        var s = Set<String>(), r: [(Int, Int, Int)] = []
        let idx = g.simplificar(10)
        func meter(_ z: Int, _ x: Int, _ y: Int) {
            let n = 1 << z
            guard x >= 0, y >= 0, x < n, y < n else { return }
            if s.insert("\(z)/\(x)/\(y)").inserted { r.append((z, x, y)) }
        }
        for z in zMin...zMax {
            let n = Double(1 << z)
            for k in 0..<idx.count {
                let a = idx[k], b = k + 1 < idx.count ? idx[k + 1] : idx[k]
                let pasos = max(1, Int(Gpx.metros(g.lat[a], g.lon[a], g.lat[b], g.lon[b]) / 60))
                for j in 0...pasos {
                    let f = Double(j) / Double(pasos)
                    let la = g.lat[a] + (g.lat[b] - g.lat[a]) * f, lo = g.lon[a] + (g.lon[b] - g.lon[a]) * f
                    let fx = (lo + 180) / 360 * n
                    let fy = (1 - log(tan(la * .pi / 180) + 1 / cos(la * .pi / 180)) / .pi) / 2 * n
                    let x = Int(fx), y = Int(fy)
                    meter(z, x, y)
                    let dx = fx - Double(x), dy = fy - Double(y)
                    if dx < 0.15 { meter(z, x - 1, y) } else if dx > 0.85 { meter(z, x + 1, y) }
                    if dy < 0.15 { meter(z, x, y - 1) } else if dy > 0.85 { meter(z, x, y + 1) }
                }
            }
        }
        return r
    }

    /// Guarda las teselas de un estilo a lo largo de la ruta. OpenStreetMap: hasta 250 teselas de zoom 13 o más
    /// (sus normas lo limitan). IGN e ICGC (servicios públicos): hasta 900, con zoom hasta 16. Como en Android.
    static func guardar(_ g: Gpx, estilo: String, cat: Bool, progreso: @escaping (Int, Int) -> Void) async -> Bool {
        let osm = Estilos.esOsm(estilo)
        let limite = osm ? 250 : 900
        var zMax = osm ? 15 : 16
        var lista: [(Int, Int, Int)] = []
        while zMax >= 13 {
            lista = pasillo(g, 10, zMax)
            if lista.filter({ $0.0 >= 13 }).count <= limite { break }
            zMax -= 1
        }
        if zMax < 13 { lista = pasillo(g, 10, 12) }
        var faltan: [(String, Int, Int, Int)] = []
        for k in Estilos.capas(estilo, cat) where k != "dem" {
            for (z, x, y) in lista where !FileManager.default.fileExists(atPath: ruta(guardadas, k, z, x, y).path) { faltan.append((k, z, x, y)) }
        }
        let total = faltan.count
        if total == 0 { return true }
        var hechas = 0
        let s = shared.sesion
        for trozo in stride(from: 0, to: faltan.count, by: 6) {
            await withTaskGroup(of: Void.self) { grupo in
                for (k, z, x, y) in faltan[trozo..<min(trozo + 6, faltan.count)] {
                    grupo.addTask {
                        let dest = ruta(guardadas, k, z, x, y)
                        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let c = ruta(carpeta, k, z, x, y)
                        if FileManager.default.fileExists(atPath: c.path) { try? FileManager.default.copyItem(at: c, to: dest); return }
                        guard let u = url(k, z, x, y), let res = try? await s.data(from: u), (res.1 as? HTTPURLResponse)?.statusCode == 200 else { return }
                        try? res.0.write(to: dest)
                    }
                }
            }
            hechas = min(total, trozo + 6)
            let h = hechas
            await MainActor.run { progreso(h, total) }
        }
        return true
    }
}
