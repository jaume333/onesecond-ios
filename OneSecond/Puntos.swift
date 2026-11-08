import Foundation
import CoreLocation

/// Puntos de control (Rider 1000 y Ronda la Llana): la app apunta el paso cuando entra en el radio de un punto
/// y lo envía a …/paso. La lista se descarga de …/puntos cuando cambia su versión («pv»).
final class Puntos {
    struct P { let id: Int; let lat: Double; let lon: Double; let r: Double; let n: String }

    let aj: Ajustes
    private(set) var lista: [P] = []
    private(set) var pasados = Set<Int>()
    private(set) var version = ""
    private(set) var salida = true
    private(set) var ultimoNombre = ""
    private(set) var ultimoT: Int64 = 0
    private var ultimaDescarga: Date = .distantPast
    private var urlCargada = ""
    private var muestras: [(t: Double, d: Double)] = []
    private var muestrasDe = -1
    private(set) var distSig: Double = -1
    private static let escalones = [1, 3, 5, 10, 20, 30, 60, 120, 300, 600, 900]

    init(_ aj: Ajustes) { self.aj = aj }

    /// Lo guardado en el móvil (por si se arranca sin cobertura). Si la dirección ha cambiado, se empieza de cero.
    func cargarGuardados(_ url: String) {
        if url == urlCargada { return }
        urlCargada = url
        lista = []; pasados = []
        let d = UserDefaults.standard
        let k = aj.p.id + "_pt_"
        if d.string(forKey: k + "url") != url {
            for c in ["lista", "pasados", "version", "salida", "pendientes", "ultimo_nombre", "ultimo_t"] { d.removeObject(forKey: k + c) }
            d.set(url, forKey: k + "url")
            version = ""
            return
        }
        leerLista(aj.json("pt_lista") as? [[String: Any]] ?? [])
        pasados = Set((aj.json("pt_pasados") as? [Int]) ?? [])
        version = d.string(forKey: k + "version") ?? ""
        salida = d.object(forKey: k + "salida") as? Bool ?? true
        ultimoNombre = d.string(forKey: k + "ultimo_nombre") ?? ""
        ultimoT = (d.object(forKey: k + "ultimo_t") as? NSNumber)?.int64Value ?? 0
    }

    private func leerLista(_ a: [[String: Any]]) {
        lista = a.compactMap { o in
            let lat = o.dbl("lat"), lon = o.dbl("lon")
            if lat.isNaN || lon.isNaN { return nil }
            return P(id: o.int("id"), lat: lat, lon: lon, r: max(20, min(5000, o.dbl("r", 150))), n: o.str("n"))
        }
    }

    func hayQueDescargar(_ pv: String?) -> Bool {
        if let pv = pv, !pv.isEmpty, pv != version { return true }
        return version.isEmpty && Date().timeIntervalSince(ultimaDescarga) > 300
    }

    func descargar(_ base: String) async {
        ultimaDescarga = Date()
        let (c, data) = await Red.pedir(base + "/puntos")
        guard c == 200 else { return }
        let o = Red.objeto(data)
        let a = o["puntos"] as? [[String: Any]] ?? []
        leerLista(a)
        if let hechos = o["pasados"] as? [Any] {
            pasados = Set(hechos.compactMap { ($0 as? Int) ?? ($0 as? NSNumber)?.intValue })
            for x in pendientesLista() { pasados.insert(x.int("punto")) }
        }
        salida = o["salida"] == nil ? true : o.bool("salida", true)
        version = o.str("pv")
        aj.guardarJson("pt_lista", a)
        aj.guardarJson("pt_pasados", Array(pasados))
        let d = UserDefaults.standard, k = aj.p.id + "_pt_"
        d.set(version, forKey: k + "version")
        d.set(salida, forKey: k + "salida")
    }

    /// Cada posición: si está dentro del radio de un punto no pasado, se apunta el paso. Devuelve cada cuántos segundos
    /// conviene la próxima posición (Int.max = no hay puntos).
    func revisar(_ l: CLLocation) -> (gps: Int, paso: Bool) {
        if lista.isEmpty { return (Int.max, false) }
        let buena = l.horizontalAccuracy >= 0 && l.horizontalAccuracy <= 80
        var dmin = Double.greatestFiniteMagnitude
        var paso = false
        for p in lista where !pasados.contains(p.id) {
            let d = l.distance(from: CLLocation(latitude: p.lat, longitude: p.lon))
            if buena && d <= p.r && salida {
                registrar(p, l, d)
                paso = true
                continue
            }
            dmin = min(dmin, max(0, d - p.r))
        }
        if buena { anotar(l) }
        if dmin == .greatestFiniteMagnitude { return (Int.max, paso) }
        if !buena { return (10, paso) }
        var seg = dmin / 45.0 * 0.6
        if l.speed >= 0 && l.speed < 2 { seg = max(seg, 30) }
        var g = 1
        for e in Puntos.escalones where Double(e) <= seg { g = e }
        return (g, paso)
    }

    private func registrar(_ p: P, _ l: CLLocation, _ d: Double) {
        pasados.insert(p.id)
        ultimoNombre = p.n
        ultimoT = ahoraMs()
        var pend = pendientesLista()
        pend.append(["punto": p.id, "time": Int64(l.timestamp.timeIntervalSince1970 * 1000), "lat": l.coordinate.latitude,
                     "lon": l.coordinate.longitude, "acc": l.horizontalAccuracy, "dist": (d * 10).rounded() / 10])
        aj.guardarJson("pt_pendientes", pend)
        aj.guardarJson("pt_pasados", Array(pasados))
        let dd = UserDefaults.standard, k = aj.p.id + "_pt_"
        dd.set(ultimoNombre, forKey: k + "ultimo_nombre")
        dd.set(NSNumber(value: ultimoT), forKey: k + "ultimo_t")
    }

    private func pendientesLista() -> [[String: Any]] { aj.json("pt_pendientes") as? [[String: Any]] ?? [] }

    /// Envía los pasos pendientes a …/paso.
    func enviarPasos(_ base: String) async {
        let pend = pendientesLista()
        if pend.isEmpty { return }
        let (c, _) = await Red.pedir(base + "/paso", cuerpo: pend)
        if c == 200 {
            let ahora = pendientesLista()
            aj.guardarJson("pt_pendientes", Array(ahora.dropFirst(pend.count)))
        }
    }

    func cargarDemo() {
        lista = [P(id: 1, lat: 41.60, lon: 2.10, r: 150, n: "Salida · Sabadell"), P(id: 2, lat: 41.70, lon: 2.00, r: 150, n: "Coll de Pradell"),
                 P(id: 3, lat: 41.80, lon: 1.90, r: 150, n: "Montserrat"), P(id: 4, lat: 41.90, lon: 1.80, r: 150, n: "Cardona"),
                 P(id: 5, lat: 42.00, lon: 1.70, r: 150, n: "Solsona"), P(id: 6, lat: 41.60, lon: 2.11, r: 150, n: "Llegada · Sabadell")]
        pasados = [1, 2, 3]
        let ahora = Date().timeIntervalSince1970
        muestras = [(ahora - 600, 24400), (ahora, 12400)]
        muestrasDe = 3
        distSig = 12400
    }

    // ---------- para la pantalla ----------
    var total: Int { lista.count }
    var hechos: Int { lista.filter { pasados.contains($0.id) }.count }
    var siguiente: P? { lista.first { !pasados.contains($0.id) } }

    private func anotar(_ l: CLLocation) {
        guard let i = lista.firstIndex(where: { !pasados.contains($0.id) }) else { distSig = -1; muestras = []; return }
        let p = lista[i]
        let d = l.distance(from: CLLocation(latitude: p.lat, longitude: p.lon))
        if i != muestrasDe { muestras = []; muestrasDe = i }
        let tt = Date().timeIntervalSince1970
        if muestras.last == nil || tt - muestras.last!.t >= 5 { muestras.append((tt, d)) }
        while muestras.count > 2 && tt - muestras[0].t > 20 * 60 { muestras.removeFirst() }
        distSig = d
    }

    /// Hora prevista de llegada al próximo punto (con lo que se ha acercado de verdad los últimos minutos).
    var llegada: Date? {
        guard muestras.count >= 2, distSig >= 0 else { return nil }
        let a = muestras.first!, b = muestras.last!
        let dt = b.t - a.t
        if dt < 180 { return nil }
        let v = (a.d - b.d) / dt
        if v < 1.5 { return nil }
        let seg = b.d / v
        if seg > 86400 { return nil }
        return Date(timeIntervalSince1970: b.t + seg)
    }
}
