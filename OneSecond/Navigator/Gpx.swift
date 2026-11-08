import Foundation

/// One Second Navigator: una ruta GPX ya leída y preparada para navegar (como Gpx.java de Android 1.57).
/// Puntos del track (o de la ruta si no hay track), distancia acumulada, subida acumulada (con un filtro para que
/// los saltos pequeños del GPS no sumen), puntos de paso (wpt) y las curvas fuertes calculadas con la forma del track.
final class Gpx {
    static let R = 6371008.8
    var nombre = ""
    var lat: [Double] = [], lon: [Double] = [], ele: [Double] = [], dist: [Double] = [], subida: [Double] = []
    var conAltura = false
    var pasos: [Paso] = []
    var giros: [Giro] = []

    struct Paso { let lat: Double; let lon: Double; let nombre: String }
    /// Curva fuerte: a qué distancia del inicio, hacia qué lado (-1 izquierda, 1 derecha) y cuánto gira.
    struct Giro {
        let d: Double, grados: Double, lado: Int
        init(_ d: Double, _ g: Double) { self.d = d; grados = abs(g); lado = g < 0 ? -1 : 1 }
        /// 1 curva, 2 curva cerrada, 3 herradura
        var tipo: Int { grados >= 150 ? 3 : grados >= 100 ? 2 : 1 }
    }

    var n: Int { lat.count }
    var total: Double { dist.last ?? 0 }
    var subidaTotal: Double { subida.last ?? 0 }

    enum Fallo: Error { case sinPuntos }

    static func leer(_ data: Data) throws -> Gpx {
        let l = Lector()
        let p = XMLParser(data: data)
        p.shouldProcessNamespaces = false
        p.delegate = l
        p.parse()
        let pts = l.trk.count >= 2 ? l.trk : l.rte
        guard pts.count >= 2 else { throw Fallo.sinPuntos }
        let g = Gpx()
        g.pasos = l.pasos
        g.nombre = !l.nombreMeta.isEmpty ? l.nombreMeta : !l.nombreTrk.isEmpty ? l.nombreTrk : l.nombreRte
        try g.preparar(pts)
        return g
    }

    private final class Lector: NSObject, XMLParserDelegate {
        var trk: [[Double]] = [], rte: [[Double]] = []
        var pasos: [Paso] = []
        var nombreTrk = "", nombreMeta = "", nombreRte = ""
        private var punto: [Double]? = nil
        private var tipoPunto: String? = nil, nombreWpt: String? = nil, padre = ""
        private var texto = ""

        private func local(_ n: String) -> String { n.split(separator: ":").last.map(String.init) ?? n }

        func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            let t = local(e)
            texto = ""
            if t == "trkpt" || t == "rtept" || t == "wpt" {
                if let la = Double(a["lat"]?.trimmingCharacters(in: .whitespaces) ?? ""), let lo = Double(a["lon"]?.trimmingCharacters(in: .whitespaces) ?? "") {
                    punto = [la, lo, .nan]
                } else { punto = nil }
                tipoPunto = t; nombreWpt = nil
            } else if t == "trk" || t == "rte" || t == "metadata" { padre = t }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) { texto += s }
        func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            let t = local(e)
            let v = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "ele", punto != nil { punto![2] = Double(v) ?? .nan }
            else if t == "name" {
                if tipoPunto != nil { nombreWpt = v }
                else if padre == "trk" && nombreTrk.isEmpty { nombreTrk = v }
                else if padre == "metadata" && nombreMeta.isEmpty { nombreMeta = v }
                else if padre == "rte" && nombreRte.isEmpty { nombreRte = v }
            } else if t == "trkpt" || t == "rtept" || t == "wpt" {
                if let p = punto {
                    if t == "trkpt" { trk.append(p) } else if t == "rtept" { rte.append(p) }
                    else { pasos.append(Paso(lat: p[0], lon: p[1], nombre: nombreWpt ?? "")) }
                }
                punto = nil; tipoPunto = nil
            }
            texto = ""
        }
    }

    private func preparar(_ pts: [[Double]]) throws {
        var p: [[Double]] = []
        for q in pts {
            if abs(q[0]) > 90 || abs(q[1]) > 180 { continue }
            if let u = p.last, Gpx.metros(u[0], u[1], q[0], q[1]) < 0.5 { continue }
            p.append(q)
        }
        guard p.count >= 2 else { throw Fallo.sinPuntos }
        let n = p.count
        lat = p.map { $0[0] }; lon = p.map { $0[1] }; ele = p.map { $0[2] }
        dist = [Double](repeating: 0, count: n); subida = [Double](repeating: 0, count: n)
        for i in 1..<n { dist[i] = dist[i - 1] + Gpx.metros(lat[i - 1], lon[i - 1], lat[i], lon[i]) }
        conAltura = ele.filter { !$0.isNaN }.count > n / 2
        var ult = ele.first { !$0.isNaN } ?? .nan
        for i in 0..<n { if ele[i].isNaN { ele[i] = ult.isNaN ? 0 : ult } else { ult = ele[i] } }
        var ref = ele[0], ac = 0.0
        for i in 0..<n {
            let d = ele[i] - ref
            if d >= 4 { ac += d; ref = ele[i] } else if d <= -4 { ref = ele[i] }
            subida[i] = ac
        }
        calcularGiros()
    }

    /// Curvas fuertes: el cambio de rumbo entre 30 m antes y 30 m después de cada punto.
    private func calcularGiros() {
        let n = self.n
        var cambio = [Double](repeating: 0, count: n)
        var a = 0, b = 0
        for i in 0..<n {
            while a < i && dist[i] - dist[a + 1] >= 30 { a += 1 }
            if b < i { b = i }
            while b < n - 1 && dist[b] - dist[i] < 30 { b += 1 }
            if dist[i] - dist[a] < 20 || dist[b] - dist[i] < 20 { continue }
            cambio[i] = Gpx.norm(Gpx.rumbo(lat[i], lon[i], lat[b], lon[b]) - Gpx.rumbo(lat[a], lon[a], lat[i], lon[i]))
        }
        var tmp: [Giro] = []
        var i = 0
        while i < n {
            if abs(cambio[i]) < 55 { i += 1; continue }
            let s = cambio[i] < 0 ? -1.0 : 1.0
            var mejor = i
            while i < n && abs(cambio[i]) >= 55 && (cambio[i] < 0 ? -1.0 : 1.0) == s {
                if abs(cambio[i]) > abs(cambio[mejor]) { mejor = i }
                i += 1
            }
            tmp.append(Giro(dist[mejor], cambio[mejor]))
        }
        for g in tmp {
            if let u = giros.last, g.d - u.d < 80 {
                if g.grados > u.grados { giros[giros.count - 1] = g }
                continue
            }
            giros.append(g)
        }
    }

    static func metros(_ la1: Double, _ lo1: Double, _ la2: Double, _ lo2: Double) -> Double {
        let x = (lo2 - lo1) * .pi / 180 * cos((la1 + la2) / 2 * .pi / 180)
        let y = (la2 - la1) * .pi / 180
        return R * (x * x + y * y).squareRoot()
    }
    /// Rumbo en grados (0 norte, 90 este).
    static func rumbo(_ la1: Double, _ lo1: Double, _ la2: Double, _ lo2: Double) -> Double {
        let f1 = la1 * .pi / 180, f2 = la2 * .pi / 180, dl = (lo2 - lo1) * .pi / 180
        let y = sin(dl) * cos(f2), x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    static func norm(_ g0: Double) -> Double {
        var g = g0
        while g > 180 { g -= 360 }
        while g < -180 { g += 360 }
        return g
    }

    /// Índice del último punto con distancia acumulada <= d.
    func indice(_ d: Double) -> Int {
        if d <= 0 { return 0 }
        var lo = 0, hi = n - 1
        if d >= dist[hi] { return hi }
        while hi - lo > 1 { let m = (lo + hi) / 2; if dist[m] <= d { lo = m } else { hi = m } }
        return lo
    }
    func alturaEn(_ d: Double) -> Double {
        let i = indice(d)
        if i >= n - 1 { return ele[n - 1] }
        let t = (d - dist[i]) / max(0.01, dist[i + 1] - dist[i])
        return ele[i] + (ele[i + 1] - ele[i]) * t
    }
    func subidaEn(_ d: Double) -> Double { subida[min(n - 1, max(0, indice(d)))] }

    /// Punto de la ruta más cercano a (la, lo) buscando en los tramos [desde, hasta).
    /// Devuelve (metros hasta la ruta, distancia sobre la ruta, latitud, longitud, índice del tramo).
    func cercano(_ la: Double, _ lo: Double, _ desde0: Int, _ hasta0: Int) -> (m: Double, d: Double, lat: Double, lon: Double, i: Int)? {
        let desde = max(0, desde0), hasta = min(n - 1, hasta0)
        guard desde < hasta else { return nil }
        let k = cos(la * .pi / 180) * .pi / 180 * Gpx.R, m = .pi / 180 * Gpx.R
        var mejor: (Double, Double, Double, Double, Int)? = nil
        var mejorD = Double.greatestFiniteMagnitude
        for i in desde..<hasta {
            let ax = (lon[i] - lo) * k, ay = (lat[i] - la) * m
            let bx = (lon[i + 1] - lo) * k, by = (lat[i + 1] - la) * m
            let dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy
            let t = l2 <= 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / l2))
            let px = ax + dx * t, py = ay + dy * t, d2 = px * px + py * py
            if d2 < mejorD {
                mejorD = d2
                mejor = (d2.squareRoot(), dist[i] + (dist[i + 1] - dist[i]) * t, lat[i] + (lat[i + 1] - lat[i]) * t, lon[i] + (lon[i + 1] - lon[i]) * t, i)
            }
        }
        return mejor.map { (m: $0.0, d: $0.1, lat: $0.2, lon: $0.3, i: $0.4) }
    }

    /// Índices de los puntos que quedan al simplificar el track (Douglas-Peucker, tolerancia en metros) para dibujarlo.
    func simplificar(_ tol: Double) -> [Int] {
        let n = self.n
        var queda = [Bool](repeating: false, count: n)
        queda[0] = true; queda[n - 1] = true
        let k = cos(lat[0] * .pi / 180) * .pi / 180 * Gpx.R, m = .pi / 180 * Gpx.R
        var pila: [(Int, Int)] = [(0, n - 1)]
        while let (a, b) = pila.popLast() {
            if b - a < 2 { continue }
            let ax = lon[a] * k, ay = lat[a] * m, bx = lon[b] * k, by = lat[b] * m
            let dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy
            var peor = -1.0, ip = -1
            for i in (a + 1)..<b {
                let px = lon[i] * k - ax, py = lat[i] * m - ay
                let d: Double
                if l2 <= 0 { d = (px * px + py * py).squareRoot() }
                else {
                    let t = max(0, min(1, (px * dx + py * dy) / l2))
                    let qx = px - dx * t, qy = py - dy * t
                    d = (qx * qx + qy * qy).squareRoot()
                }
                if d > peor { peor = d; ip = i }
            }
            if peor > tol && ip > 0 { queda[ip] = true; pila.append((a, ip)); pila.append((ip, b)) }
        }
        return (0..<n).filter { queda[$0] }
    }
}
