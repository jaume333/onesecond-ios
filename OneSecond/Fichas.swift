import SwiftUI
import MapKit
import CryptoKit
import CoreLocation

/// Ronda la Llana: FICHAS SECRETAS (como FichasDatos.java de Android 1.57). El itinerario es secreto: el servidor
/// solo da cada ficha (track del tramo en GPX, puntos GPS y punto de paso) cuando el piloto está en el punto donde
/// se abre. Las cerradas llegan cifradas: sin cobertura, el QR del punto las abre en el móvil, y se avisa al
/// servidor cuando vuelve la cobertura.
enum FichasDatos {
    struct Ficha: Identifiable {
        var id: Int { n }
        var n = 0
        var abierta = false, local = false
        var t: Double = 0                     // cuándo se abrió (s)
        var tramo = "", cierre = "", gpx = ""
        var km: Double = 0
        var punto: [String: Any]? = nil       // punto de paso del final {nombre, dir, lat, lon}
        var puntos: [[String: Any]] = []      // puntos GPS [{n, lat, lon}]
        var abre: [String: Any]? = nil        // solo la siguiente cerrada: {lat, lon, radio, desde, nombre}
        var cifrada: [String: Any]? = nil

        var tienePunto: Bool { punto?["lat"] is NSNumber && punto?["lon"] is NSNumber }
        var nombrePunto: String { punto?.str("nombre") ?? "" }
    }

    private static var d: UserDefaults { .standard }

    static func base(_ p: Prueba) -> String? { Ajustes(p: p).base }

    static var guardado: [String: Any] {
        (try? JSONSerialization.jsonObject(with: d.data(forKey: "fichas_datos") ?? Data())) as? [String: Any] ?? [:]
    }
    static var locales: [String: Any] {
        get { (try? JSONSerialization.jsonObject(with: d.data(forKey: "fichas_locales") ?? Data())) as? [String: Any] ?? [:] }
        set { d.set(try? JSONSerialization.data(withJSONObject: newValue), forKey: "fichas_locales") }
    }
    static var actualizado: Double { d.double(forKey: "fichas_t") }

    /// Las fichas: las del servidor y, encima, las abiertas en el móvil con el QR.
    static func fichas() -> [Ficha] {
        let g = guardado, loc = locales
        guard let a = g["fichas"] as? [[String: Any]] else { return [] }
        var l: [Ficha] = []
        for x in a {
            if x.bool("abierta") { l.append(de(x, local: false)) }
            else if let y = loc[String(x.int("n"))] as? [String: Any] { l.append(de(y, local: true)) }
            else { var f = Ficha(); f.n = x.int("n"); f.abre = x["abre"] as? [String: Any]; f.cifrada = x["cifrada"] as? [String: Any]; l.append(f) }
        }
        // la siguiente cerrada se abre en el punto de paso de la anterior (aunque esta se haya abierto con el QR)
        if l.count > 1 {
            for i in 1..<l.count where !l[i].abierta && l[i].abre == nil && l[i - 1].abierta && l[i - 1].tienePunto {
                let ant = l[i - 1]
                l[i].abre = ["lat": ant.punto?.dbl("lat") ?? 0, "lon": ant.punto?.dbl("lon") ?? 0,
                             "radio": (g["radio"] as? NSNumber)?.doubleValue ?? 100, "nombre": ant.nombrePunto]
            }
        }
        return l
    }

    private static func de(_ x: [String: Any], local: Bool) -> Ficha {
        var f = Ficha()
        f.n = x.int("n"); f.abierta = true; f.local = local
        f.t = x.dbl("t"); f.tramo = x.str("tramo"); f.cierre = x.str("cierre"); f.km = x.dbl("km")
        f.punto = x["punto"] as? [String: Any]; f.puntos = x["puntos"] as? [[String: Any]] ?? []; f.gpx = x.str("gpx")
        if f.tramo == "null" { f.tramo = "" }
        if f.cierre == "null" { f.cierre = "" }
        return f
    }

    static func abiertas(_ p: Prueba) -> Int { fichas().filter(\.abierta).count }

    /// Pide las fichas al servidor (con la posición si la hay: si está en el punto, se abre la ficha). false sin cobertura.
    static func actualizar(_ p: Prueba, _ l: CLLocation?) async -> Bool {
        guard let b = base(p) else { return false }
        await sincronizarQr(p)
        let r: (Int, Data)
        if let l = l {
            r = await Red.pedir(b + "/fichas/abrir", cuerpo: ["lat": l.coordinate.latitude, "lon": l.coordinate.longitude,
                                                              "acc": l.horizontalAccuracy, "mock": false])
        } else {
            r = await Red.pedir(b + "/fichas")
        }
        let j = Red.objeto(r.1)
        guard r.0 == 200, j.str("status") == "ok" else { return false }
        // las abiertas en el móvil que el servidor ya da por abiertas dejan de ser «locales»
        var loc = locales
        for x in j["fichas"] as? [[String: Any]] ?? [] where x.bool("abierta") { loc.removeValue(forKey: String(x.int("n"))) }
        locales = loc
        d.set(r.1, forKey: "fichas_datos")
        d.set(Date().timeIntervalSince1970, forKey: "fichas_t")
        return true
    }

    /// ¿Hay fichas en esta Ronda? (total, abiertas) o nil sin cobertura.
    static func resumen(_ p: Prueba) async -> (Int, Int)? {
        guard let b = base(p) else { return nil }
        let (c, data) = await Red.pedir(b + "/fichas?resumen=1")
        guard c == 200 else { return nil }
        let j = Red.objeto(data)
        let r = (j.int("total"), (j["abiertas"] as? [Any])?.count ?? 0)
        d.set(r.0, forKey: "fichas_total")
        return r
    }

    // ---------- QR del punto (sin cobertura) ----------
    /// Lee «https://onesecond.es/ronda/ficha?n=3&k=…». Devuelve (n, k) o nil si no es un QR de ficha.
    static func leerQr(_ txt: String) -> (Int, String)? {
        guard let u = URLComponents(string: txt.trimmingCharacters(in: .whitespacesAndNewlines)), u.path.hasSuffix("/ficha"),
              let n = u.queryItems?.first(where: { $0.name == "n" })?.value, let k = u.queryItems?.first(where: { $0.name == "k" })?.value,
              n.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil, k.range(of: #"^[0-9a-fA-F]{32}$"#, options: .regularExpression) != nil,
              let num = Int(n) else { return nil }
        return (num, k.lowercased())
    }

    /// Abre la ficha n con su clave en el móvil (sin internet). true si la clave es la buena.
    static func abrirConQr(_ n: Int, _ clave: String) -> Bool {
        guard let f = fichas().first(where: { $0.n == n }) else { return false }
        if f.abierta { apuntarQr(n, clave); return true }
        guard let cif = f.cifrada, let datos = descifrar(clave, cif),
              var x = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any] else { return false }
        x["t"] = Date().timeIntervalSince1970
        var loc = locales
        loc[String(n)] = x
        locales = loc
        apuntarQr(n, clave)
        return true
    }

    private static func apuntarQr(_ n: Int, _ k: String) {
        var p = (try? JSONSerialization.jsonObject(with: d.data(forKey: "fichas_qr_pend") ?? Data())) as? [[String: Any]] ?? []
        p.append(["n": n, "k": k, "t": Date().timeIntervalSince1970])
        d.set(try? JSONSerialization.data(withJSONObject: p), forKey: "fichas_qr_pend")
    }

    /// Los QR leídos sin cobertura se mandan al servidor cuando vuelve (así la organización ve que pasó).
    static func sincronizarQr(_ p: Prueba) async {
        guard let b = base(p) else { return }
        let pend = (try? JSONSerialization.jsonObject(with: d.data(forKey: "fichas_qr_pend") ?? Data())) as? [[String: Any]] ?? []
        if pend.isEmpty { return }
        var quedan: [[String: Any]] = []
        for x in pend {
            let (c, _) = await Red.pedir(b + "/fichas/qr", cuerpo: x)
            if c == -1 || c >= 500 || c == 429 { quedan.append(x) }      // 403 (QR viejo): no se repite
        }
        d.set(try? JSONSerialization.data(withJSONObject: quedan), forKey: "fichas_qr_pend")
    }

    /// El mismo cifrado que el servidor: flujo SHA-256 (clave + sal + contador) y HMAC-SHA256 para saber que la clave es la buena.
    static func descifrar(_ claveHex: String, _ cif: [String: Any]) -> Data? {
        guard let k = hex(claveHex), let sal = Data(base64Encoded: cif.str("s")), let ct = Data(base64Encoded: cif.str("c")),
              let m = Data(base64Encoded: cif.str("m")) else { return nil }
        var h = HMAC<SHA256>(key: SymmetricKey(data: k))
        h.update(data: sal); h.update(data: ct)
        let mac = Data(h.finalize()).prefix(16)
        guard mac == m else { return nil }
        var out = [UInt8](repeating: 0, count: ct.count)
        let c = [UInt8](ct)
        var bloque: [UInt8] = []
        for i in 0..<c.count {
            if i % 32 == 0 {
                var s = SHA256()
                s.update(data: k); s.update(data: sal)
                var cont = UInt64(i / 32).bigEndian
                s.update(data: Data(bytes: &cont, count: 8))
                bloque = [UInt8](s.finalize())
            }
            out[i] = c[i] ^ bloque[i % 32]
        }
        return Data(out)
    }

    private static func hex(_ s: String) -> Data? {
        var b = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
            guard let v = UInt8(s[i..<j], radix: 16) else { return nil }
            b.append(v); i = j
        }
        return b
    }

    /// Para las capturas del simulador.
    static func cargarDemo() {
        let j: [String: Any] = ["status": "ok", "evento": "Ronda 2026", "radio": 100, "fichas": [
            ["n": 1, "abierta": true, "t": Date().timeIntervalSince1970 - 7200, "tramo": "Sabadell – Monistrol", "km": 38.2, "cierre": "",
             "punto": ["nombre": "Monistrol de Montserrat", "lat": 41.61, "lon": 1.84], "puntos": [], "gpx": ""],
            ["n": 2, "abierta": true, "t": Date().timeIntervalSince1970 - 2400, "tramo": "Monistrol – Cardona", "km": 46.7, "cierre": "13:30",
             "punto": ["nombre": "Cardona", "lat": 41.91, "lon": 1.68], "puntos": [["n": "Coll de Port", "lat": 41.75, "lon": 1.79]], "gpx": ""],
            ["n": 3, "abierta": false],
        ]]
        d.set(try? JSONSerialization.data(withJSONObject: j), forKey: "fichas_datos")
        d.set(Date().timeIntervalSince1970 - 120, forKey: "fichas_t")
        locales = [:]
    }
}

private enum FC {
    static let fondo = Color(hex: 0x0B0F15), panel = Color(hex: 0x121822), borde = Color(hex: 0x253042), texto = Color(hex: 0xE9EEF5)
    static let suave = Color(hex: 0x8D9BB0), cobre = Color(hex: 0xB8693A), cobreClaro = Color(hex: 0xF0C9A8), verde = Color(hex: 0x3FBF7F)
    static let azul = Color(hex: 0x4A90E2), oroMeta = Color(hex: 0xFFD257)
}

/// «Mis fichas»: las abiertas, la que toca (bloqueada, sin decir cuántas hay) y la meta tras la última.
struct FichasView: View {
    @EnvironmentObject var central: Central
    @Environment(\.dismiss) var cerrar
    let p: Prueba
    @State private var lista: [FichasDatos.Ficha] = []
    @State private var escaneando = false
    @State private var ver: FichasDatos.Ficha? = nil
    @State private var celebrar: Int? = nil
    @State private var antes = -1
    private let reloj = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ZStack {
                FC.fondo.ignoresSafeArea()
                VStack(spacing: 0) {
                    cabecera.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                    ScrollView { contenido.padding(.horizontal, 14).padding(.bottom, 14) }
                    VStack(spacing: 6) {
                        Button { escaneando = true } label: {
                            Text("▣   " + TxRonda.t("fi_qr")).font(.system(size: 15.5, weight: .medium)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 52).background(RoundedRectangle(cornerRadius: 14).fill(FC.azul))
                        }
                        Text(estado).font(.system(size: 12)).foregroundColor(FC.suave).multilineTextAlignment(.center)
                    }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 14)
                }
                if let n = celebrar {
                    VStack(spacing: 8) {
                        Text("📜").font(.system(size: 54))
                        Text(TxRonda.f("fi_desbloqueada", n)).font(.custom("TeXGyrePagella-Bold", size: 24)).foregroundColor(.white)
                        Text(TxRonda.t("fi_toca")).font(.footnote).foregroundColor(FC.cobreClaro)
                    }
                    .padding(28).background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: 0x1D1712)))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(FC.cobre, lineWidth: 2))
                    .onTapGesture { celebrar = nil; ver = lista.first { $0.n == n } }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $escaneando) {
                EscanerQR { s in escaneando = false; leido(s) }.ignoresSafeArea()
            }
            .sheet(item: $ver) { f in FichaVerView(p: p, f: f) { cerrar() }.environmentObject(central).preferredColorScheme(.dark) }
        }
        .onAppear {
            if Demo.activo { FichasDatos.cargarDemo() }
            lista = FichasDatos.fichas(); antes = lista.filter(\.abierta).count
            cargar()
        }
        .onReceive(reloj) { _ in cargar() }
    }

    private var cabecera: some View {
        let aj = central.aj(p)
        let ev = FichasDatos.guardado.str("evento")
        let total = lista.count, ab = lista.filter(\.abierta).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button { cerrar() } label: { Text("‹").font(.system(size: 30)).foregroundColor(FC.suave).padding(.trailing, 10) }
                Image("ic_ronda").resizable().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(TxRonda.t("fi_titulo")).font(.custom("TeXGyrePagella-Bold", size: 21)).foregroundColor(FC.texto)
                    Text(Self.subtitulo(ev, aj.dorsal, aj.nombrePiloto)).font(.system(size: 12.5)).foregroundColor(FC.suave)
                }.padding(.leading, 12)
                Spacer()
            }
            if total > 0 {
                Text(TxRonda.f(ab >= total ? "fi_llevas_ultima" : "fi_llevas", ab)).font(.system(size: 12)).foregroundColor(FC.suave).padding(.top, 12)
            }
        }
    }

    @ViewBuilder private var contenido: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TxRonda.t("fi_fichas").uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.7).foregroundColor(FC.suave)
                .padding(.top, 10).padding(.leading, 2)
            if FichasDatos.base(p) == nil {
                vacio("🔗", TxRonda.t("fi_sin_vincular"))
            } else if lista.isEmpty {
                vacio("📜", FichasDatos.actualizado == 0 ? TxRonda.t("fi_cargando") : TxRonda.t("fi_no_hay"))
            } else {
                let ultima = lista.lastIndex { $0.abierta } ?? -1
                let sig = lista.firstIndex { !$0.abierta }
                ForEach(Array(lista.enumerated()), id: \.offset) { i, f in
                    if f.abierta { tarjetaAbierta(f, actual: i == ultima, esUltima: i == lista.count - 1) }
                    else if i == sig { tarjetaSiguiente(f) }
                }
                if ultima == lista.count - 1, let u = lista.last { tarjetaMeta(u) }
                Text(TxRonda.t("fi_nota")).font(.system(size: 12)).foregroundColor(FC.suave).lineSpacing(3).padding(.horizontal, 4).padding(.top, 10)
            }
        }
    }

    private func vacio(_ ic: String, _ txt: String) -> some View {
        VStack(spacing: 12) {
            Text(ic).font(.system(size: 40))
            Text(txt).font(.system(size: 14.5)).foregroundColor(FC.suave).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 40).padding(.bottom, 30)
    }

    private func insignia(_ s: String, fondo: Color, color: Color, borde: Color?, lado: CGFloat, tam: CGFloat) -> some View {
        Text(s).font(.custom("TeXGyrePagella-Bold", size: tam)).foregroundColor(color).frame(width: lado, height: lado)
            .background(Circle().fill(fondo)).overlay(Circle().stroke(borde ?? .clear, lineWidth: 1.5))
    }

    private func fila<C: View>(fondo: Color, borde: Color, grosor: CGFloat, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 12) { c() }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(fondo))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(borde, lineWidth: grosor))
    }

    private func textos(_ a: String, _ b: String, _ colorB: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(a).font(.custom("TeXGyrePagella-Bold", size: 16)).foregroundColor(FC.texto)
            Text(b).font(.system(size: 12)).foregroundColor(colorB)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tarjetaAbierta(_ f: FichasDatos.Ficha, actual: Bool, esUltima: Bool) -> some View {
        let dorada = actual && esUltima
        let fondo: Color = dorada ? Color(hex: 0x221D0E) : actual ? Color(hex: 0x1D1712) : FC.panel
        let borde: Color = dorada ? FC.oroMeta : actual ? FC.cobre : FC.borde
        let colorSub: Color = dorada ? FC.oroMeta : actual ? FC.cobreClaro : FC.suave
        let titulo = TxRonda.t("fi_ficha") + " \(f.n)" + (f.tramo.isEmpty ? "" : " · " + f.tramo)
        var sub: String
        if actual {
            sub = TxRonda.t("fi_abierta") + " · " + Self.km(f.km)
            if !f.cierre.isEmpty { sub += " · " + TxRonda.f("fi_cierra_a", f.cierre) }
        } else {
            let a: String = f.t > 0 ? TxRonda.f("fi_abierta_a", Self.hora(f.t)) : TxRonda.t("fi_abierta")
            sub = a + " · " + Self.km(f.km)
        }
        if f.local { sub += " · " + TxRonda.t("fi_con_qr") }
        if esUltima { sub = TxRonda.t("fi_ultima") + "\n" + sub }
        return Button { ver = f } label: {
            fila(fondo: fondo, borde: borde, grosor: actual ? 2 : 1) {
                if dorada { insignia("\(f.n)", fondo: FC.oroMeta, color: Color(hex: 0x2A1D08), borde: nil, lado: 42, tam: 20) }
                else if actual { insignia("\(f.n)", fondo: FC.cobre, color: .white, borde: nil, lado: 42, tam: 20) }
                else { insignia("✓", fondo: Color(hex: 0x173326), color: Color(hex: 0x7FE0AD), borde: FC.verde, lado: 42, tam: 18) }
                textos(titulo, sub, colorSub)
                Text("›").font(.system(size: 24)).foregroundColor(actual ? FC.cobreClaro : FC.suave)
            }
        }
    }

    private func tarjetaSiguiente(_ f: FichasDatos.Ficha) -> some View {
        var sub = TxRonda.t("fi_se_abre_paso")
        if let a = f.abre {
            sub = TxRonda.f("fi_se_abre_en", a.str("nombre"))
            let desde = a.dbl("desde")
            if desde > 0 && desde > Date().timeIntervalSince1970 { sub += " " + TxRonda.f("fi_a_las", Self.hora(desde)) }
            if let l = central.ultimaLocalizacion {
                let dd = l.distance(from: CLLocation(latitude: a.dbl("lat"), longitude: a.dbl("lon")))
                sub += "\n" + (dd < 1000 ? TxRonda.f("fi_estas_m", Int(dd.rounded())) : TxRonda.f("fi_estas_km", dd / 1000))
            }
        }
        return fila(fondo: FC.panel, borde: FC.borde, grosor: 1) {
            insignia("🔒", fondo: Color(hex: 0x161D28), color: Color(hex: 0x4B5A70), borde: Color(hex: 0x33415A), lado: 42, tam: 17)
            textos(TxRonda.t("fi_ficha") + " \(f.n)", sub, FC.suave)
        }
    }

    private func tarjetaMeta(_ u: FichasDatos.Ficha) -> some View {
        fila(fondo: FC.panel, borde: Color(hex: 0x5A4A1A), grosor: 1) {
            insignia("🏁", fondo: Color(hex: 0x2A2410), color: FC.oroMeta, borde: Color(hex: 0x6B5A1F), lado: 42, tam: 17)
            textos(TxRonda.t("fi_meta_t"), u.nombrePunto.isEmpty ? TxRonda.t("fi_meta_s") : u.nombrePunto, FC.suave)
        }
    }

    private var estado: String {
        let t0 = FichasDatos.actualizado
        if t0 == 0 { return TxRonda.t("fi_nota_qr") }
        let min = Int((Date().timeIntervalSince1970 - t0) / 60)
        return (min < 1 ? TxRonda.t("fi_actualizado_ahora") : TxRonda.f("fi_actualizado_hace", min)) + " · " + TxRonda.t("fi_nota_qr")
    }

    private func cargar() {
        if Demo.activo { return }
        Task {
            let ok = await FichasDatos.actualizar(p, central.ultimaLocalizacion)
            lista = FichasDatos.fichas()
            comprobarNuevas()
            if !ok && FichasDatos.actualizado == 0 { central.breve(TxRonda.t("fi_sin_red"), error: true) }
        }
    }

    private func comprobarNuevas() {
        let ab = lista.filter(\.abierta).count
        if antes >= 0 && ab > antes, let u = lista.last(where: { $0.abierta }) { celebrar = u.n }
        antes = ab
    }

    private func leido(_ s: String) {
        guard let (n, k) = FichasDatos.leerQr(s) else { central.breve(TxRonda.t("fi_qr_mal"), error: true); return }
        if FichasDatos.guardado["fichas"] == nil { central.breve(TxRonda.t("fi_qr_sin_datos"), error: true); return }
        if FichasDatos.abrirConQr(n, k) {
            lista = FichasDatos.fichas()
            comprobarNuevas()
            Task { await FichasDatos.sincronizarQr(p) }
        } else { central.breve(TxRonda.t("fi_qr_mal"), error: true) }
    }

    static func subtitulo(_ ev: String, _ dorsal: String, _ nombre: String) -> String {
        var s = ev.isEmpty ? "Ronda la Llana" : ev
        if !dorsal.isEmpty { s += " · " + TxRonda.t("dorsal") + " " + dorsal }
        if !nombre.isEmpty { s += " · " + nombre }
        return s
    }

    static func km(_ km: Double) -> String { String(format: km >= 100 ? "%.0f km" : "%.1f km", locale: Idioma.locale, km) }
    static func hora(_ s: Double) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date(timeIntervalSince1970: s)) }
}

/// Una ficha abierta: el tramo en el mapa (salida en verde, puntos GPS en rojo con sus coordenadas, punto de paso),
/// la hora de cierre, «Navegar este tramo» (Navigator) y cada punto con su posición.
struct FichaVerView: View {
    @Environment(\.dismiss) var cerrar
    let p: Prueba
    let f: FichasDatos.Ficha
    let cerrarTodo: () -> Void

    var body: some View {
        let g = f.gpx.isEmpty ? nil : try? Gpx.leer(Data(f.gpx.utf8))
        ZStack {
            FC.fondo.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button { cerrar() } label: { Text("‹").font(.system(size: 30)).foregroundColor(FC.suave) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(TxRonda.t("fi_ficha") + " \(f.n)").font(.custom("TeXGyrePagella-Bold", size: 21)).foregroundColor(FC.texto)
                            if !f.tramo.isEmpty { Text(f.tramo).font(.system(size: 13)).foregroundColor(FC.suave) }
                        }
                    }
                    MapaFicha(gpx: g, f: f).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 14))
                    HStack(spacing: 8) {
                        chip("🛣 " + FichasView.km(f.km), FC.panel, Color(hex: 0xC9D3DF), FC.borde)
                        if !f.cierre.isEmpty { chip("⏱ " + TxRonda.f("fi_cierra_a", f.cierre), Color(hex: 0x2A1D14), FC.cobreClaro, Color(hex: 0x6E3519)) }
                        if !f.puntos.isEmpty { chip(TxRonda.f("fi_n_puntos", f.puntos.count), FC.panel, Color(hex: 0xC9D3DF), FC.borde) }
                    }
                    Button { navegar() } label: {
                        Text("▶   " + TxRonda.t("fi_navegar")).font(.system(size: 15.5, weight: .medium)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52).background(RoundedRectangle(cornerRadius: 14).fill(FC.azul))
                    }.disabled(g == nil).opacity(g == nil ? 0.5 : 1)
                    if f.tienePunto {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(TxRonda.t("fi_punto_paso").uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.7).foregroundColor(FC.suave)
                            Text(f.nombrePunto.isEmpty ? TxRonda.t("fi_punto_paso") : f.nombrePunto).font(.custom("TeXGyrePagella-Bold", size: 18)).foregroundColor(FC.texto)
                            let dir = f.punto?.str("dir") ?? ""
                            if !dir.isEmpty && dir != "null" { Text(dir).font(.system(size: 13)).foregroundColor(FC.suave) }
                            Text(coord(f.punto?.dbl("lat") ?? 0, f.punto?.dbl("lon") ?? 0)).font(.system(size: 12, design: .monospaced)).foregroundColor(FC.suave)
                            Button { irA(f.punto?.dbl("lat") ?? 0, f.punto?.dbl("lon") ?? 0) } label: {
                                chip(TxRonda.t("fi_ir_aqui"), Color(hex: 0x10284A), Color(hex: 0x9CC4F5), Color(hex: 0x2F5AA0))
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16).fill(FC.panel)).overlay(RoundedRectangle(cornerRadius: 16).stroke(FC.borde))
                    }
                    if !f.puntos.isEmpty {
                        Text(TxRonda.t("fi_puntos_gps").uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.7).foregroundColor(FC.suave).padding(.top, 4)
                        ForEach(Array(f.puntos.enumerated()), id: \.offset) { i, o in
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(.custom("TeXGyrePagella-Bold", size: 15)).foregroundColor(.white).frame(width: 30, height: 30)
                                    .background(Circle().fill(Color(hex: 0xE8262B)))
                                VStack(alignment: .leading, spacing: 2) {
                                    let nom = o.str("n")
                                    Text(nom.isEmpty || nom == "null" ? TxRonda.t("fi_punto") + " \(i + 1)" : nom).font(.custom("TeXGyrePagella-Bold", size: 14.5)).foregroundColor(FC.texto)
                                    Text(coord(o.dbl("lat"), o.dbl("lon"))).font(.system(size: 12, design: .monospaced)).foregroundColor(FC.suave)
                                }
                                Spacer()
                            }
                            .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(FC.panel))
                        }
                    }
                }.padding(16)
            }
        }
    }

    private func chip(_ s: String, _ fondo: Color, _ color: Color, _ borde: Color) -> some View {
        Text(s).font(.system(size: 12.5, weight: .medium)).foregroundColor(color).padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(fondo)).overlay(Capsule().stroke(borde))
    }

    private func coord(_ la: Double, _ lo: Double) -> String { String(format: "N %.6f  E %.6f", la, lo) }

    private func irA(_ la: Double, _ lo: Double) {
        let it = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: la, longitude: lo)))
        it.name = f.nombrePunto.isEmpty ? TxRonda.t("fi_punto_paso") : f.nombrePunto
        it.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func navegar() {
        guard !f.gpx.isEmpty, let r = try? Rutas.guardar(Data(f.gpx.utf8), nombreArchivo: "Ronda_ficha_\(f.n).gpx", origen: "ronda", carpetaSrv: "ronda_fichas", remoto: nil) else { return }
        cerrar()
        cerrarTodo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NotificationCenter.default.post(name: .abrirRuta, object: r.archivo) }
    }
}

final class MarcaTrafico: MKPointAnnotation {}

extension Notification.Name { static let abrirRuta = Notification.Name("abrirRuta") }

/// El mapa de la ficha (Apple Maps): el tramo, la salida en verde, los puntos GPS en rojo y el punto de paso.
struct MapaFicha: UIViewRepresentable {
    let gpx: Gpx?
    let f: FichasDatos.Ficha

    func makeCoordinator() -> Delegado { Delegado() }
    final class Delegado: NSObject, MKMapViewDelegate {
        func mapView(_ m: MKMapView, rendererFor o: MKOverlay) -> MKOverlayRenderer {
            let r = MKPolylineRenderer(overlay: o); r.strokeColor = UIColor(red: 0.29, green: 0.56, blue: 0.89, alpha: 1); r.lineWidth = 5; return r
        }
        func mapView(_ m: MKMapView, viewFor a: MKAnnotation) -> MKAnnotationView? {
            let v = MKMarkerAnnotationView(annotation: a, reuseIdentifier: nil)
            let sub = (a.subtitle ?? nil) ?? ""
            if a is MarcaTrafico {
                v.markerTintColor = UIColor(red: 0.91, green: 0.45, blue: 0.05, alpha: 1); v.glyphText = "⚠️"
                return v
            }
            switch sub {
            case "salida": v.markerTintColor = .systemGreen
            case "paso": v.markerTintColor = UIColor(red: 0.72, green: 0.41, blue: 0.23, alpha: 1); v.glyphText = "🏁"
            default: v.markerTintColor = .systemRed
            }
            return v
        }
    }

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.overrideUserInterfaceStyle = .dark
        m.showsUserLocation = true
        var coords: [CLLocationCoordinate2D] = []
        if let g = gpx { coords = (0..<g.n).map { CLLocationCoordinate2D(latitude: g.lat[$0], longitude: g.lon[$0]) } }
        if !coords.isEmpty {
            m.addOverlay(MKPolyline(coordinates: coords, count: coords.count))
            let s = MKPointAnnotation(); s.coordinate = coords[0]; s.title = TxRonda.t("fi_salida"); s.subtitle = "salida"; m.addAnnotation(s)
        }
        for (i, o) in f.puntos.enumerated() {
            let a = MKPointAnnotation(); a.coordinate = .init(latitude: o.dbl("lat"), longitude: o.dbl("lon"))
            a.title = o.str("n").isEmpty ? TxRonda.t("fi_punto") + " \(i + 1)" : o.str("n"); a.subtitle = "gps"; m.addAnnotation(a)
        }
        if f.tienePunto {
            let a = MKPointAnnotation(); a.coordinate = .init(latitude: f.punto?.dbl("lat") ?? 0, longitude: f.punto?.dbl("lon") ?? 0)
            a.title = f.nombrePunto; a.subtitle = "paso"; m.addAnnotation(a)
        }
        // incidencias de tráfico (DGT / Trànsit) del tramo de esta ficha
        for x in TraficoMapa.items(ficha: f.n) {
            let a = MarcaTrafico(); a.coordinate = .init(latitude: x.dbl("lat"), longitude: x.dbl("lon"))
            a.title = Trafico.icono(x.str("cat")) + " " + Trafico.titulo(x.str("cat"))
            let car = x.str("carretera"); a.subtitle = car == "null" ? "" : car; m.addAnnotation(a)
        }
        DispatchQueue.main.async {
            if !coords.isEmpty, let o = m.overlays.first { m.setVisibleMapRect(o.boundingMapRect, edgePadding: .init(top: 30, left: 30, bottom: 30, right: 30), animated: false) }
            else { m.showAnnotations(m.annotations, animated: false) }
        }
        return m
    }
    func updateUIView(_ v: MKMapView, context: Context) {}
}
