import SwiftUI
import AVFoundation
import Network
import UserNotifications

/// AVISOS DE TRÁFICO de la DGT y del Servei Català de Trànsit (como ronda/Trafico.java de Android 1.57).
/// El servidor mira, con cada envío de posiciones, si en el tramo hay por delante un accidente, un corte, un vehículo
/// parado, una retención o un obstáculo, y la respuesta trae {"trf": [...]}. La app lo dice POR VOZ (por el
/// intercomunicador del casco si está conectado por Bluetooth), lo enseña en grande si la app está abierta y deja
/// una notificación.
@MainActor
enum Trafico {
    private static let voz = AVSpeechSynthesizer()

    static func titulo(_ cat: String) -> String {
        switch cat {
        case "accidente": return t("Accidente", "Accident", "Accident")
        case "cortada": return t("Carretera cortada", "Carretera tallada", "Road closed")
        case "parado": return t("Vehículo parado", "Vehicle aturat", "Stopped vehicle")
        case "retencion": return t("Retención", "Retenció", "Traffic queue")
        case "obstaculo": return t("Obstáculo en la calzada", "Obstacle a la calçada", "Obstacle on the road")
        default: return t("Incidencia", "Incidència", "Incident")
        }
    }
    static func icono(_ cat: String) -> String {
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

/// La red (datos móviles, wifi o sin conexión) que se añade a cada posición, para el mapa de cobertura del recorrido.
final class RedActual {
    static let shared = RedActual()
    private let m = NWPathMonitor()
    private(set) var tipo = ""
    private init() {
        m.pathUpdateHandler = { [weak self] p in
            self?.tipo = p.status != .satisfied ? "n" : p.usesInterfaceType(.wifi) ? "w" : "m"
        }
        m.start(queue: DispatchQueue(label: "red"))
    }
    var json: String { tipo.isEmpty ? "" : ",\"red\":\"" + tipo + "\"" }
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
