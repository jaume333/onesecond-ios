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
        sub: ["Un QR por consumición · ranking", "Un QR per consumició · rànquing", "One QR per drink · leaderboard"],
        icono: "ic_cazatopo", metal: [0x281A0E, 0x966234, 0x4E321A], direccion: "https://onesecond.es/cazatopo/")
    static let ruta66 = MiniJuego(id: "ruta66", nombre: "Ruta 66",
        sub: ["Carrera en la pantalla gigante", "Cursa a la pantalla gegant", "Race on the big screen"],
        icono: "ic_ruta66", metal: [0x461A12, 0xD67838, 0x78301C], direccion: "https://onesecond.es/ruta66/movil")
    static let todos = [cazatopo, ruta66]

    /// ¿Es un QR de un mini juego? Devuelve el juego, o nil.
    static func deQR(_ s: String) -> MiniJuego? {
        guard let u = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["onesecond.es", "www.onesecond.es"].contains(u.host ?? "") else { return nil }
        if u.path.hasPrefix("/cazatopo") { return cazatopo }
        if u.path.hasPrefix("/ruta66") { return ruta66 }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { if w.web.canGoBack { w.web.goBack() } else { cerrar() } } label: {
                    Text("‹").font(.system(size: 30)).foregroundColor(.suave).padding(.horizontal, 8)
                }
                Image(juego.icono).resizable().frame(width: 30, height: 30)
                Text(juego.nombre).font(.custom("TeXGyrePagella-Bold", size: 19)).foregroundColor(.texto)
                Spacer()
                Button { escaneando = true } label: {
                    Text("▣  " + t("Escanear QR", "Escanejar QR", "Scan QR")).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(Color.azul))
                }
                Button { cerrar() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.suave).padding(6) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            ZStack(alignment: .top) {
                WebJuegoVista(w: w)
                if w.cargando < 1 { ProgressView(value: w.cargando).tint(.azul) }
            }
        }
        .background(Color(hex: 0x0B0F15).ignoresSafeArea())
        .onAppear { w.abrir(inicio ?? juego.direccion) }
        .sheet(isPresented: $escaneando) {
            EscanerQR { s in
                escaneando = false
                if let j = MiniJuego.deQR(s) {
                    if j.id == juego.id { w.abrir(s) }
                    else { cerrar(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NotificationCenter.default.post(name: .abrirMiniJuego, object: [j.id, s]) } }
                } else {
                    aviso = t("Este QR no es de un mini juego de One Second.", "Aquest QR no és d'un mini joc de One Second.", "This QR is not from a One Second mini game.")
                }
            }.ignoresSafeArea()
        }
        .alert(aviso ?? "", isPresented: Binding(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) { Button("OK") {} }
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
