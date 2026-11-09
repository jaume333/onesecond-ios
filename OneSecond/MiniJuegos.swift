import SwiftUI
import WebKit

/// MINI JUEGOS (como MiniJuego.java de Android 1.58): Caza al Topo (onesecond.es/cazatopo: cada consumición trae un QR
/// con una partida) y Ruta 66 (onesecond.es/ruta66: la carrera de la pantalla gigante; cada móvil es una moto).
/// Son las mismas webs, dentro de la app; arriba, «Escanear QR» (el QR del ticket o el de la pantalla gigante).
struct MiniJuego: Identifiable {
    let id: String
    let nombre: String
    let sub: [String]
    let icono: String
    let metal: [UInt32]
    let direccion: String
    var subtitulo: String { t(sub[0], sub[1], sub[2]) }

    static let cazatopo = MiniJuego(id: "cazatopo", nombre: "Caza al Topo",
        sub: ["Caza todos los topos · Ranking", "Caça tots els talps · Rànquing", "Whack all the moles · Leaderboard"],
        icono: "ic_cazatopo", metal: [0x281A0E, 0x966234, 0x4E321A], direccion: "https://onesecond.es/cazatopo/")
    static let ruta66 = MiniJuego(id: "ruta66", nombre: "Ruta 66",
        sub: ["Gana a todos con tu Chopper", "Guanya a tothom amb la teva Chopper", "Beat everyone with your Chopper"],
        icono: "ic_ruta66", metal: [0x461A12, 0xD67838, 0x78301C], direccion: "https://onesecond.es/ruta66/movil")
    static let bingo = MiniJuego(id: "bingo", nombre: "Bingo Motero",
        sub: ["Cartones con QR · Avisos de línea y bingo", "Cartrons amb QR · Avisos de línia i bingo", "QR bingo cards · Line and bingo alerts"],
        icono: "ic_bingo", metal: [0x22180E, 0xB08440, 0x563C1C], direccion: BingoAvisos.web)
    static let todos = [cazatopo, ruta66, bingo]
    /// El aviso de la II Motoweekend (13-15 nov. 2026) sale hasta el 16 de noviembre de 2026 a las 00:00 (hora de Madrid).
    static let finAviso: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 16; c.timeZone = TimeZone(identifier: "Europe/Madrid")
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantPast
    }()

    /// Lo que se escribe a mano: la dirección del QR (con o sin https://) o, en Caza al Topo, solo el código del ticket
    /// (10 letras y números, con o sin espacios o guiones). Devuelve (juego, dirección) o nil.
    static func deTexto(_ s: String, en: MiniJuego) -> (MiniJuego, String)? {
        var x = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if x.isEmpty { return nil }
        if x.lowercased().hasPrefix("onesecond.es") || x.lowercased().hasPrefix("www.onesecond.es") { x = "https://" + x }
        if x.lowercased().hasPrefix("http"), let j = deQR(x) { return (j, x) }
        let codigo = x.uppercased().filter { "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".contains($0) }
        // Bingo Motero: el código del ticket son 8 letras y números (XXXX-XXXX)
        if en.id == "bingo", codigo.count == 8 { let a = String(codigo.prefix(4)), b = String(codigo.suffix(4)); return (en, BingoAvisos.web + "c/" + a + "-" + b) }
        if en.id == "cazatopo", (6...16).contains(codigo.count) { return (en, "https://onesecond.es/cazatopo/?t=" + codigo) }
        return nil
    }

    /// ¿Es un QR de un mini juego? Devuelve el juego, o nil.
    static func deQR(_ s: String) -> MiniJuego? {
        guard let u = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["onesecond.es", "www.onesecond.es"].contains(u.host ?? "") else { return nil }
        if u.path.hasPrefix("/cazatopo") { return cazatopo }
        if u.path.hasPrefix("/ruta66") { return ruta66 }
        if u.path.hasPrefix("/bingo") { return bingo }
        return nil
    }
}

struct MiniJuegoView: View {
    @Environment(\.dismiss) var cerrar
    let juego: MiniJuego
    var inicio: String? = nil
    @StateObject private var w = WebJuego()
    @State private var escaneando = false
    @State private var aviso: String? = nil
    @State private var escribir = false
    @State private var texto = ""

    var body: some View {
        GeometryReader { g in
        let estrecho = g.size.width < 400          // iPhone SE, mini...: barra más compacta
        VStack(spacing: 0) {
            HStack(spacing: estrecho ? 6 : 10) {
                Button { if w.web.canGoBack { w.web.goBack() } else { cerrar() } } label: {
                    Text("‹").font(.system(size: 30)).foregroundColor(.suave).padding(.horizontal, estrecho ? 4 : 8)
                }
                Image(juego.icono).resizable().frame(width: estrecho ? 26 : 30, height: estrecho ? 26 : 30)
                Text(juego.nombre).font(.custom("TeXGyrePagella-Bold", size: estrecho ? 16 : 19)).foregroundColor(.texto)
                    .lineLimit(1).minimumScaleFactor(0.6).layoutPriority(-1)
                Spacer(minLength: 4)
                Button { escaneando = true } label: {
                    Text("▣ " + (estrecho ? "QR" : t("Escanear QR", "Escanejar QR", "Scan QR"))).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .lineLimit(1).fixedSize().padding(.horizontal, estrecho ? 10 : 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(Color.azul))
                }
                Button { texto = ""; escribir = true } label: {
                    Text("⌨︎" + (estrecho ? "" : " " + t("Código", "Codi", "Code"))).font(.system(size: 14, weight: .bold)).foregroundColor(.texto)
                        .lineLimit(1).fixedSize().padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(Color.borde, lineWidth: 1.5))
                }
                Button { cerrar() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.suave).padding(4) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            ZStack(alignment: .top) {
                WebJuegoVista(w: w)
                if w.cargando < 1 { ProgressView(value: w.cargando).tint(.azul) }
            }
        }
        }
        .background(Color(hex: 0x0B0F15).ignoresSafeArea())
        .sheet(isPresented: $escribir) {
            // iOS 15: el cuadro de escribir va en una hoja (las alertas con campo de texto son de iOS 16)
            VStack(alignment: .leading, spacing: 14) {
                Text(t("Código del QR", "Codi del QR", "QR code")).font(.custom("TeXGyrePagella-Bold", size: 22)).foregroundColor(.texto)
                Text(juego.id != "ruta66"
                     ? t("Escribe el código que hay debajo del QR del ticket (o la dirección entera).", "Escriu el codi que hi ha sota el QR del tiquet (o l'adreça sencera).", "Type the code under the QR on the ticket (or the full address).")
                     : t("Escribe la dirección que sale debajo del QR de la pantalla gigante.", "Escriu l'adreça que surt sota el QR de la pantalla gegant.", "Type the address shown under the QR on the big screen."))
                    .font(.system(size: 14)).foregroundColor(.suave)
                TextField(juego.id != "ruta66" ? t("Código del ticket", "Codi del tiquet", "Ticket code") : "onesecond.es/ruta66/…", text: $texto)
                    .textInputAutocapitalization(juego.id != "ruta66" ? .characters : .never).disableAutocorrection(true)
                    .font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundColor(.white)
                    .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color.panel))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borde, lineWidth: 1.5))
                    .submitLabel(.go).onSubmit { escribir = false; abrirTexto() }
                HStack(spacing: 10) {
                    Button { escribir = false } label: {
                        Text(t("Cancelar", "Cancel·lar", "Cancel")).font(.system(size: 16, weight: .medium)).foregroundColor(.suave)
                            .frame(maxWidth: .infinity).frame(height: 50).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borde))
                    }
                    Button { escribir = false; abrirTexto() } label: {
                        Text(t("Abrir", "Obrir", "Open")).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 50).background(RoundedRectangle(cornerRadius: 12).fill(Color.azul))
                    }
                }
                Spacer()
            }
            .padding(22).background(Color(hex: 0x0B0F15).ignoresSafeArea()).preferredColorScheme(.dark)
        }
        .onAppear {
            w.abrir(inicio ?? juego.direccion)
            if juego.id == "bingo" { BingoAvisos.shared.pedirPermiso(); BingoAvisos.shared.abierto = true }
        }
        .onDisappear { BingoAvisos.shared.abierto = false; BingoAvisos.shared.arrancar() }
        .sheet(isPresented: $escaneando) {
            EscanerQR { s in
                escaneando = false
                if let (j, u) = MiniJuego.deTexto(s, en: juego) {
                    if j.id == juego.id { w.abrir(u) }
                    else { cerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NotificationCenter.default.post(name: .abrirMiniJuego, object: [j.id, u]) } }
                } else {
                    aviso = t("Este QR no es de un mini juego de One Second.", "Aquest QR no és d'un mini joc de One Second.", "This QR is not from a One Second mini game.")
                }
            }.ignoresSafeArea()
        }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
    }
}

extension MiniJuegoView {
    func abrirTexto() {
        guard let (j, u) = MiniJuego.deTexto(texto, en: juego) else {
            aviso = t("Ese código no es válido. Revisa que esté bien escrito.", "Aquest codi no és vàlid. Revisa que estigui ben escrit.", "That code is not valid. Check it is typed correctly.")
            return
        }
        if j.id == juego.id { w.abrir(u) }
        else { cerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NotificationCenter.default.post(name: .abrirMiniJuego, object: [j.id, u]) } }
    }
}

final class WebJuego: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var cargando: Double = 0
    let web: WKWebView
    private var obs: NSKeyValueObservation?

    override init() {
        let c = WKWebViewConfiguration()
        c.allowsInlineMediaPlayback = true                        // la cámara de la propia web (su lector de QR)
        c.mediaTypesRequiringUserActionForPlayback = []           // los sonidos del juego
        c.websiteDataStore = .default()                           // el jugador se queda guardado (no se vuelve a pedir)
        // en el bingo la web ofrece «activar avisos» (web push, o «añádela a la pantalla de inicio» en iPhone), que en la
        // app no hace falta: los avisos los saca la app (BingoAvisos)
        c.userContentController.addUserScript(WKUserScript(source: "if(location.pathname.indexOf('/bingo')===0){var s=document.createElement('style');s.textContent='.avisos{display:none!important}';document.documentElement.appendChild(s);}",
                                                           injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        web = WKWebView(frame: .zero, configuration: c)
        super.init()
        web.isOpaque = false
        web.backgroundColor = UIColor(Color(hex: 0x0B0F15))
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        obs = web.observe(\.estimatedProgress) { [weak self] v, _ in DispatchQueue.main.async { self?.cargando = v.estimatedProgress } }
    }

    func abrir(_ s: String) { if let u = URL(string: s) { web.load(URLRequest(url: u)) } }

    /// Fuera de onesecond.es (patrocinadores, WhatsApp...) se abre fuera de la app.
    func webView(_ v: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let u = a.request.url else { decisionHandler(.allow); return }
        let h = u.host ?? ""
        if u.scheme == "https" && (h == "onesecond.es" || h == "www.onesecond.es") || u.scheme == "about" || u.scheme == "blob" || u.scheme == "data" {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        UIApplication.shared.open(u)
    }

    func webView(_ v: WKWebView, didFinish n: WKNavigation!) {
        if v.url?.path.hasPrefix("/bingo") == true { Task { @MainActor in BingoAvisos.shared.arrancar() } }
    }

    func webView(_ v: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if a.targetFrame == nil { v.load(a.request) }
        return nil
    }

    /// El lector de QR de la propia web pide la cámara: se deja (el iPhone pregunta el permiso la primera vez).
    @available(iOS 15.0, *)
    func webView(_ v: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.hasSuffix("onesecond.es") ? .grant : .deny)
    }
}

struct WebJuegoVista: UIViewRepresentable {
    let w: WebJuego
    func makeUIView(context: Context) -> WKWebView { w.web }
    func updateUIView(_ v: WKWebView, context: Context) {}
}

extension Notification.Name { static let abrirMiniJuego = Notification.Name("abrirMiniJuego") }
