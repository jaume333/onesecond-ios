import Foundation
import UIKit
import WebKit
import UserNotifications

/// 1.58: avisos del BINGO MOTERO (onesecond.es/bingo), como BingoAvisos.java de Android. La web los manda con «web push»,
/// que dentro de una app no funciona; aquí la app pregunta al servidor del bingo (/bingo/api/yo, con la cookie del jugador
/// de la web) y saca ella misma las notificaciones: has cantado LÍNEA, ¡BINGO! (con el código del premio), la partida
/// empieza en X min y ¡empieza la partida! (solo si tienes cartones en ella).
/// Cada 4 s con el bingo abierto y cada 15 s con la app abierta en otra pantalla. En segundo plano iOS solo deja seguir
/// un rato; por eso el aviso de «¡empieza la partida!» se deja programado en el iPhone a la hora de la cuenta atrás.
@MainActor
final class BingoAvisos {
    static let shared = BingoAvisos()
    nonisolated static let web = "https://onesecond.es/bingo/"
    /// Dentro de la app, la web del bingo no habla de consumiciones ni de lo que se paga (eso va en la pantalla gigante):
    /// se cambian esos textos, se quita la caja de «activar avisos» (web push), porque los avisos los saca la app, y el
    /// «Escanear un ticket» / «escribe el código» de la web, porque ya están arriba («Escanear QR» y «Código»).
    nonisolated static let jsWeb = #"(function(){if(location.pathname.indexOf('/bingo')!==0)return;var s=document.createElement('style');s.textContent='.avisos,#escBtn,.sep-o{display:none!important}';document.documentElement.appendChild(s);function quitar(){var c=document.getElementById('cod');if(c){var f=c.closest('form');if(f)f.style.display='none';}try{var tx=[TXT.es.escribir_cod,TXT.ca.escribir_cod,TXT.es.esc_btn,TXT.ca.esc_btn];document.querySelectorAll('#app button,#app a').forEach(function(b){if(tx.indexOf(b.textContent.trim())>=0)b.style.display='none';});}catch(e){}}try{var o={"es": {"consumicion": "Ticket", "escanea_txt": "Cada ticket con QR es un cartón para la próxima partida (máximo 2 por partida). Toca «Escanear QR» arriba, o «Código» para escribir el código que hay debajo del QR.", "g1t": "Consigue tu ticket", "g1": "En la concentración te dan un <strong>ticket con QR</strong>: es <strong>tu cartón</strong>. ¡Guárdalo! Algunos tickets son además un <strong>abono</strong> (mira el paso 8).", "g8t": "Abono de bingo", "g8": "Algunos tickets son de <strong>abono</strong>. Escanea su QR <strong>una sola vez</strong>: además del cartón del propio ticket, te aparecerá <strong>un cartón en cada partida</strong> que empiece ese día dentro del horario que pone el ticket. No tienes que hacer nada más: los cartones llegan solos a tu móvil."}, "ca": {"consumicion": "Tiquet", "escanea_txt": "Cada tiquet amb QR és un cartró per a la propera partida (màxim 2 per partida). Toca «Escanejar QR» a dalt, o «Codi» per escriure el codi que hi ha sota el QR.", "g1t": "Aconsegueix el teu tiquet", "g1": "A la concentració et donen un <strong>tiquet amb QR</strong>: és <strong>el teu cartró</strong>. Guarda'l! Alguns tiquets són a més un <strong>abonament</strong> (mira el pas 8).", "g8t": "Abonament de bingo", "g8": "Alguns tiquets són d'<strong>abonament</strong>. Escaneja el seu QR <strong>una sola vegada</strong>: a més del cartró del mateix tiquet, et sortirà <strong>un cartró a cada partida</strong> que comenci aquell dia dins de l'horari que posa el tiquet. No has de fer res més: els cartrons arriben sols al teu mòbil."}};Object.assign(TXT.es,o.es);Object.assign(TXT.ca,o.ca);if(typeof rehacer==='function')rehacer();}catch(e){}quitar();var a=document.getElementById('app');if(a)new MutationObserver(quitar).observe(a,{childList:true,subtree:true});})();"#
    var abierto = false { didSet { if abierto { ahora() } } }
    private var reloj: Timer?
    private var trabajando = false
    private var espera: TimeInterval = 15
    private var fondo: UIBackgroundTaskIdentifier = .invalid
    private let def = UserDefaults.standard

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in BingoAvisos.shared.aSegundoPlano() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in BingoAvisos.shared.arrancar() }
        }
    }

    /// Al abrir la app y al abrir el bingo: empieza a vigilar si este iPhone ya juega al bingo.
    func arrancar() {
        leerCookie { [weak self] tok in
            guard let self = self, tok != nil else { return }
            self.programar(0.2)
        }
    }

    func pedirPermiso() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func ahora() { programar(0.2) }

    private func programar(_ s: TimeInterval) {
        reloj?.invalidate()
        reloj = Timer.scheduledTimer(withTimeInterval: s, repeats: false) { _ in
            Task { @MainActor in BingoAvisos.shared.vuelta() }
        }
    }

    private func vuelta() {
        if !trabajando {
            trabajando = true
            Task {
                await mirar()
                trabajando = false
            }
        }
        programar(abierto ? 4 : espera)
    }

    /// En segundo plano iOS deja unos segundos más: se aprovechan para un último vistazo.
    private func aSegundoPlano() {
        if fondo != .invalid { UIApplication.shared.endBackgroundTask(fondo) }
        fondo = UIApplication.shared.beginBackgroundTask(withName: "bingo") { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                UIApplication.shared.endBackgroundTask(self.fondo); self.fondo = .invalid
            }
        }
        Task { await mirar() }
    }

    /// El token del jugador: la cookie «bingo_jug» de la web (la deja el WKWebView); se guarda por si acaso.
    private func leerCookie(_ fin: @escaping (String?) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cs in
            Task { @MainActor in
                if let c = cs.first(where: { $0.name == "bingo_jug" && $0.domain.hasSuffix("onesecond.es") }), !c.value.isEmpty {
                    self.def.set(c.value, forKey: "bingo_tok")
                    fin(c.value)
                } else {
                    let t = self.def.string(forKey: "bingo_tok") ?? ""
                    fin(t.isEmpty ? nil : t)
                }
            }
        }
    }

    private func token() -> String? {
        let t = def.string(forKey: "bingo_tok") ?? ""
        return t.isEmpty ? nil : t
    }

    private func mirar() async {
        guard let tok = token(), let u = URL(string: BingoAvisos.web + "api/yo?i=" + (Idioma.codigo == "ca" ? "ca" : "es")) else { return }
        var r = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        r.httpShouldHandleCookies = false
        r.setValue("bingo_jug=" + tok, forHTTPHeaderField: "Cookie")
        guard let (data, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        procesar(d)
    }

    private func procesar(_ d: [String: Any]) {
        guard let jug = d["jugador"] as? [String: Any] else { espera = 60; return }
        let apodo = jug["apodo"] as? String ?? ""
        let pub = d["publico"] as? [String: Any] ?? [:]
        let par = pub["partida"] as? [String: Any]
        let cartones = d["cartones"] as? [[String: Any]] ?? []
        let nombres = d["nombres"] as? [String: Any] ?? [:]
        let actual = (par?["num"] as? NSNumber)?.intValue ?? 0
        let estado = par?["estado"] as? String ?? ""
        let proxima = par == nil ? 1 : (estado == "abierta" ? actual : actual + 1)
        func tiene(_ n: Int) -> Bool { n > 0 && cartones.contains { ($0["partida"] as? NSNumber)?.intValue == n } }
        func nombre(_ n: Int) -> String {
            if let s = nombres[String(n)] as? String, !s.isEmpty { return s }
            if (par?["num"] as? NSNumber)?.intValue == n, let s = par?["nombre"] as? String, !s.isEmpty { return s }
            let b = pub["nombre_base"] as? String ?? ""
            return (b.isEmpty ? "Bingo" : b) + " \(n)"
        }
        let tengoActual = tiene(actual), tengoProxima = tiene(proxima)

        // 1) premios nuevos (línea o bingo). La primera vez solo se apuntan, sin avisar de los antiguos.
        let primera = def.object(forKey: "bingo_vistos") == nil
        var vistos = Set(def.stringArray(forKey: "bingo_vistos") ?? [])
        for x in d["premios"] as? [[String: Any]] ?? [] {
            let id = "\((x["id"] as? NSNumber)?.int64Value ?? 0)"
            if vistos.contains(id) { continue }
            vistos.insert(id)
            if primera || (x["entregado"] as? Bool ?? false) || (x["cerrado"] as? Bool ?? false) { continue }
            let bingo = x["tipo"] as? String == "bingo"
            let premio = pub[bingo ? "premio_bingo" : "premio_linea"] as? String ?? ""
            let tit = bingo ? t("🏆 ¡BINGO, \(apodo)!", "🏆 BINGO, \(apodo)!", "🏆 BINGO, \(apodo)!")
                            : t("🎉 ¡Has cantado LÍNEA, \(apodo)!", "🎉 Has cantat LÍNIA, \(apodo)!", "🎉 You got a LINE, \(apodo)!")
            let num = (x["partida"] as? NSNumber)?.intValue ?? 0
            let cuerpo = nombre(num) + " · " + t("Cartón ", "Cartró ", "Card ") + (x["carton"] as? String ?? "") + "\n"
                + t("Código del premio: ", "Codi del premi: ", "Prize code: ") + (x["codigo"] as? String ?? "") + "\n"
                + t("Enséñalo en la barra", "Ensenya'l a la barra", "Show it at the bar")
                + (premio.isEmpty ? "" : t(" y recoge: ", " i recull: ", " and collect: ") + premio)
            avisar("bingo_premio_" + id, tit, cuerpo)
        }
        def.set(Array(vistos), forKey: "bingo_vistos")

        // 2) cuenta atrás para la próxima partida (si tienes cartones en ella) y, a esa hora, «¡empieza!» programado
        let cu = pub["cuenta"] as? [String: Any]
        if let cu = cu, tengoProxima {
            let fin = (cu["fin"] as? NSNumber)?.doubleValue ?? 0, ya = (cu["ahora"] as? NSNumber)?.doubleValue ?? 0
            let seg = Int((fin - ya).rounded())
            let clave = String(Int(fin))
            if seg > 5 && clave != def.string(forKey: "bingo_cuenta") {
                def.set(clave, forKey: "bingo_cuenta")
                let tt = seg >= 90 ? "\(Int((Double(seg) / 60).rounded())) min" : "\(seg) s"
                avisar("bingo_cuenta", t("⏱ \(nombre(proxima)) empieza en \(tt)", "⏱ \(nombre(proxima)) comença en \(tt)", "⏱ \(nombre(proxima)) starts in \(tt)"),
                       t("Tus cartones ya están listos. ¡Atento a la pantalla!", "Els teus cartrons ja estan a punt. Atent a la pantalla!", "Your cards are ready. Watch the screen!"))
                avisar("bingo_empieza_\(proxima)", t("🎱 ¡Empieza \(nombre(proxima))!", "🎱 Comença \(nombre(proxima))!", "🎱 \(nombre(proxima)) is starting!"),
                       t("Tus cartones se marcan solos con cada bola.", "Els teus cartrons es marquen sols amb cada bola.", "Your cards are marked automatically with every ball."),
                       en: TimeInterval(seg))
                def.set(proxima, forKey: "bingo_empieza")      // ya va programado: no se repite al empezar
            }
        }

        // 3) empieza la partida en la que tienes cartones (si no había cuenta atrás)
        if estado == "jugando" && tengoActual && def.integer(forKey: "bingo_empieza") != actual {
            def.set(actual, forKey: "bingo_empieza")
            avisar("bingo_empieza_\(actual)", t("🎱 ¡Empieza \(nombre(actual))!", "🎱 Comença \(nombre(actual))!", "🎱 \(nombre(actual)) is starting!"),
                   t("Tus cartones se marcan solos con cada bola.", "Els teus cartrons es marquen sols amb cada bola.", "Your cards are marked automatically with every ball."))
        }
        espera = (tengoActual || tengoProxima || cu != nil) ? 15 : 60
    }

    private func avisar(_ id: String, _ titulo: String, _ cuerpo: String, en: TimeInterval = 0) {
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = cuerpo
        c.sound = .default
        c.userInfo = ["minijuego": "bingo"]
        let disparo = en > 1 ? UNTimeIntervalNotificationTrigger(timeInterval: en, repeats: false) : nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: disparo))
    }
}
