import SwiftUI
import AVFoundation
import Network
import UserNotifications
import CoreTelephony

/// AVISOS DE TRÁFICO de la DGT y del Servei Català de Trànsit (como ronda/Trafico.java de Android 1.57).
/// El servidor mira, con cada envío de posiciones, si en el tramo hay por delante un accidente, un corte, un vehículo
/// parado, una retención o un obstáculo, y la respuesta trae {"trf": [...]}. La app lo dice POR VOZ (por el
/// intercomunicador del casco si está conectado por Bluetooth), lo enseña en grande si la app está abierta y deja
/// una notificación.
@MainActor
enum Trafico {
    private static let voz = AVSpeechSynthesizer()

    nonisolated static func titulo(_ cat: String) -> String {
        switch cat {
        case "accidente": return t("Accidente", "Accident", "Accident")
        case "cortada": return t("Carretera cortada", "Carretera tallada", "Road closed")
        case "parado": return t("Vehículo parado", "Vehicle aturat", "Stopped vehicle")
        case "retencion": return t("Retención", "Retenció", "Traffic queue")
        case "obstaculo": return t("Obstáculo en la calzada", "Obstacle a la calçada", "Obstacle on the road")
        default: return t("Incidencia", "Incidència", "Incident")
        }
    }
    nonisolated static func icono(_ cat: String) -> String {
        switch cat {
        case "accidente": return "💥"
        case "cortada": return "⛔"
        case "retencion": return "🚗"
        case "obstaculo": return "🪨"
        default: return "⚠️"
        }
    }
    private static func num(_ x: Double) -> String { String(format: "%.1f", locale: Idioma.locale, x) }

    /// «a 2,3 km» (pantalla) o «a 2,3 kilómetros» (voz).
    static func distancia(_ km: Double, voz: Bool) -> String {
        if km < 0.15 { return t("aquí mismo", "just aquí", "right here") }
        if km < 1 {
            let m = max(100, Int((km * 10).rounded()) * 100)
            return t("a \(m)" + (voz ? " metros" : " m"), "a \(m)" + (voz ? " metres" : " m"), "in \(m)" + (voz ? " metres" : " m"))
        }
        let n = num(km)
        return t("a " + n + (voz ? " kilómetros" : " km"), "a " + n + (voz ? " quilòmetres" : " km"), "in " + n + (voz ? " kilometres" : " km"))
    }

    static func frase(_ x: [String: Any]) -> String {
        let c = x.str("carretera")
        let en = c.isEmpty ? "" : ", " + t("en la ", "a la ", "on the ") + c
        return t("Atención. ", "Atenció. ", "Warning. ") + titulo(x.str("cat")) + " " + distancia(x.dbl("km"), voz: true) + en + "."
    }

    static func detalle(_ x: [String: Any]) -> String {
        var s = x.str("carretera")
        if let pk = x["pk"] as? NSNumber { s += " · km " + num(pk.doubleValue) }
        let mu = x.str("municipio")
        if !mu.isEmpty && mu != "null" { s += (s.isEmpty ? "" : " · ") + mu }
        let tp = x.str("tipo")
        if !tp.isEmpty && tp != "null" { s += "\n" + tp }
        return s + "\n" + t("Fuente: DGT / Servei Català de Trànsit", "Font: DGT / Servei Català de Trànsit", "Source: DGT / Catalan Traffic Service")
    }

    static var conVoz: Bool {
        get { UserDefaults.standard.object(forKey: "trafico_voz") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "trafico_voz") }
    }

    /// Lo que llega del servidor con las posiciones.
    static func recibidos(_ trf: [[String: Any]]?, _ central: Central) {
        guard let trf = trf, !trf.isEmpty else { return }
        for x in trf {
            notificar(x)
            if conVoz { decir(frase(x)) }
            central.cartelTrafico = x
        }
    }

    private static func decir(_ s: String) {
        let ses = AVAudioSession.sharedInstance()
        try? ses.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .allowBluetoothA2DP, .interruptSpokenAudioAndMixWithOthers])
        try? ses.setActive(true)
        // se dice dos veces (con el ruido de la moto la primera se puede perder)
        for i in 0..<2 {
            let u = AVSpeechUtterance(string: s)
            u.voice = AVSpeechSynthesisVoice(language: ["es-ES", "ca-ES", "en-GB"][Idioma.actual]) ?? AVSpeechSynthesisVoice(language: "es-ES")
            if i == 1 { u.preUtteranceDelay = 0.7 }
            voz.speak(u)
        }
    }

    private static func notificar(_ x: [String: Any]) {
        let cat = x.str("cat")
        let c = UNMutableNotificationContent()
        c.title = icono(cat) + "  " + titulo(cat) + " " + distancia(x.dbl("km"), voz: false)
        c.body = detalle(x)
        c.sound = .default
        if #available(iOS 15.0, *) { c.interruptionLevel = .timeSensitive }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "trf_" + x.str("id"), content: c, trigger: nil))
    }
}

/// El cartel grande en pantalla (encima de todo) cuando llega un aviso de tráfico.
struct CartelTrafico: View {
    @EnvironmentObject var central: Central
    var body: some View {
        if let x = central.cartelTrafico {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 8) {
                    Text(Trafico.icono(x.str("cat"))).font(.system(size: 54))
                    Text(Trafico.titulo(x.str("cat"))).font(.custom("TeXGyrePagella-Bold", size: 26)).foregroundColor(.white).multilineTextAlignment(.center)
                    Text(Trafico.distancia(x.dbl("km"), voz: false)).font(.system(size: 30, weight: .heavy)).foregroundColor(Color(hex: 0xE8730C))
                    Text(Trafico.detalle(x)).font(.system(size: 14)).foregroundColor(Color(hex: 0xC9D3DF)).multilineTextAlignment(.center).padding(.top, 4)
                    Button { central.cartelTrafico = nil } label: {
                        Text(t("Entendido", "Entesos", "Got it")).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52).background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xE8730C)))
                    }.padding(.top, 10)
                }
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x1B1F27)))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0xE8730C), lineWidth: 3))
                .padding(24)
            }
            .onAppear {
                let id = x.str("id")
                DispatchQueue.main.asyncAfter(deadline: .now() + 45) { if central.cartelTrafico?.str("id") == id { central.cartelTrafico = nil } }
            }
        }
    }
}

/// La red de cada posición, para el mapa de cobertura del recorrido: "red" (m datos móviles, w wifi, n sin conexión),
/// "tec" (5G, 4G, 3G, 2G) y "cob" (0-4). El iPhone no deja a las apps leer las rayas de cobertura, así que «cob» es
/// una ESTIMACIÓN: sale de la tecnología de la red móvil y de cómo han ido de verdad los últimos envíos al servidor
/// (si fallan o tardan mucho, baja). Va marcada con "cobe":1 para que el servidor sepa que es estimada.
final class RedActual {
    static let shared = RedActual()
    private let m = NWPathMonitor()
    private let tel = CTTelephonyNetworkInfo()
    private(set) var tipo = ""
    private var ultimoEnvio: (ok: Bool, segundos: Double, cuando: Date)? = nil

    private init() {
        m.pathUpdateHandler = { [weak self] p in
            self?.tipo = p.status != .satisfied ? "n" : p.usesInterfaceType(.wifi) ? "w" : "m"
        }
        m.start(queue: DispatchQueue(label: "red"))
    }

    /// Lo que ha pasado con el último envío de posiciones (para afinar la estimación).
    func envio(ok: Bool, segundos: Double) { ultimoEnvio = (ok, segundos, Date()) }

    var tecnologia: String {
        guard let r = tel.serviceCurrentRadioAccessTechnology?.values.first else { return "" }
        if #available(iOS 14.1, *), r == CTRadioAccessTechnologyNR || r == CTRadioAccessTechnologyNRNSA { return "5G" }
        switch r {
        case CTRadioAccessTechnologyLTE: return "4G"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA, CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD: return "3G"
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyCDMA1x: return "2G"
        default: return ""
        }
    }

    /// 0-4 estimado (nil si va por wifi o no se sabe).
    var cobertura: Int? {
        if tipo == "n" { return 0 }
        if tipo != "m" { return nil }
        let tec = tecnologia
        guard var c = ["5G": 4, "4G": 3, "3G": 2, "2G": 1][tec] else { return nil }
        if let e = ultimoEnvio, Date().timeIntervalSince(e.cuando) < 300 {
            if !e.ok { c -= 2 } else if e.segundos > 6 { c -= 2 } else if e.segundos > 2.5 { c -= 1 } else if e.segundos < 0.8 && tec == "4G" { c += 1 }
        }
        return max(0, min(4, c))
    }

    var json: String {
        var s = tipo.isEmpty ? "" : ",\"red\":\"" + tipo + "\""
        let tec = tecnologia
        if tipo == "m" && !tec.isEmpty { s += ",\"tec\":\"" + tec + "\"" }
        if let c = cobertura { s += ",\"cob\":\(c),\"cobe\":1" }
        return s
    }
}

extension FichasDatos {
    /// El servidor dice cuántas fichas tiene abiertas el piloto (respuesta a las posiciones): «¡Ficha N desbloqueada!»
    static func desdeEmision(_ abiertas: Int) {
        guard abiertas >= 0 else { return }
        let d = UserDefaults.standard
        let antes = d.object(forKey: "fichas_avisadas") as? Int ?? -1
        d.set(abiertas, forKey: "fichas_avisadas")
        guard antes >= 0, abiertas > antes else { return }
        let c = UNMutableNotificationContent()
        c.title = "📜 " + TxRonda.f("fi_desbloqueada", abiertas)
        c.body = TxRonda.t("fi_toca")
        c.sound = .default
        c.userInfo = ["fichas": true]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ficha_\(abiertas)", content: c, trigger: nil))
    }
}

/// Incidencias de tráfico en el mapa (Navigator y mapa de la ficha). Las manda el servidor de la Ronda con cada envío
/// de posiciones ({"trfm": [...]}): solo las del tramo que el piloto está haciendo y que aún tiene por delante.
/// Si la app deja de recibirlas (parada, sin cobertura mucho rato), a los 15 minutos dejan de pintarse.
enum TraficoMapa {
    private static var d: UserDefaults { .standard }
    private(set) static var version = 0

    static func guardar(_ a: [[String: Any]]?) {
        guard let a = a, let datos = try? JSONSerialization.data(withJSONObject: a) else { return }
        d.set(Date().timeIntervalSince1970, forKey: "trfm_t")
        if datos != d.data(forKey: "trfm") { d.set(datos, forKey: "trfm"); version += 1 }
    }

    /// Las que valen ahora (ficha < 0: todas).
    static func items(ficha: Int = -1) -> [[String: Any]] {
        if Date().timeIntervalSince1970 - d.double(forKey: "trfm_t") > 15 * 60 { return [] }
        let a = (try? JSONSerialization.jsonObject(with: d.data(forKey: "trfm") ?? Data())) as? [[String: Any]] ?? []
        return ficha < 0 ? a : a.filter { ($0["ficha"] as? NSNumber)?.intValue == ficha }
    }

    static func colorHex(_ cat: String) -> String {
        switch cat {
        case "accidente": return "#E0404D"
        case "cortada": return "#8B1E2B"
        case "retencion": return "#D4A017"
        case "obstaculo": return "#C9821B"
        default: return "#E8730C"
        }
    }

    static func texto(_ x: [String: Any]) -> String {
        var s = Trafico.icono(x.str("cat")) + "  " + Trafico.titulo(x.str("cat"))
        let car = x.str("carretera")
        if !car.isEmpty && car != "null" { s += "\n" + car }
        if let pk = x["pk"] as? NSNumber { s += " · km " + String(format: "%.1f", locale: Idioma.locale, pk.doubleValue) }
        let mu = x.str("municipio")
        if !mu.isEmpty && mu != "null" { s += " · " + mu }
        let tp = x.str("tipo")
        if !tp.isEmpty && tp != "null" { s += "\n" + tp }
        return s + "\n" + t("DGT / Servei Català de Trànsit", "DGT / Servei Català de Trànsit", "DGT / Catalan Traffic Service")
    }

    /// Para el mapa del Navigator: [{lat, lon, c (color), i (icono), t (texto)}]
    static func json() -> String {
        let l: [[String: Any]] = items().map { x in
            ["lat": x.dbl("lat"), "lon": x.dbl("lon"), "c": colorHex(x.str("cat")), "i": Trafico.icono(x.str("cat")), "t": texto(x)]
        }
        guard let datos = try? JSONSerialization.data(withJSONObject: l), let s = String(data: datos, encoding: .utf8) else { return "[]" }
        return s
    }
}
