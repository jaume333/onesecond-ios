import SwiftUI
import WebKit
import CoreLocation

/// El mapa del Navigator (como NavMapa.java): la ruta, tu posición, el cartel de arriba (curva fuerte, fuera de ruta,
/// llegada), los botones (brújula, centrar, voz, Mapa, más) y el panel de abajo (km hechos, km faltan, subida y perfil).
struct NavMapaView: View {
    let archivo: String
    @ObservedObject private var nav = Navegacion.shared
    @EnvironmentObject var central: Central
    @Environment(\.dismiss) var cerrar
    @StateObject private var mapa = MapaWeb()
    @State private var estilo: String = UserDefaults.standard.string(forKey: "nav_estilo") ?? "oscuro"
    @AppStorage("nav_rumbo_arriba") private var rumboArriba = true
    @AppStorage("nav_min_cartel") private var cartelMin = false
    @AppStorage("nav_min_panel") private var panelMin = false
    @State private var elegirEstilo = false
    @State private var opciones = false
    @State private var confirmarParar = false
    @State private var aviso: String? = nil
    @State private var guardando: String? = nil
    @State private var errorRuta = false

    private var ruta: Gpx? { nav.archivo == archivo ? nav.ruta : nil }
    private var cat: Bool { ruta.map(Estilos.enCatalunya) ?? false }

    var body: some View {
        ZStack {
            Color(hex: 0x1A2230).ignoresSafeArea()
            if let r = ruta {
                MapaVista(mapa: mapa).ignoresSafeArea()
                    .overlay(alignment: .center) {
                        if Demo.activo && !mapa.fallo.isEmpty { Text(mapa.fallo).font(.caption).foregroundColor(.red).padding().background(Color.black) }
                    }
                    .onAppear { mapa.iniciar(r, estilo: estilo, cat: cat, rumboArriba: rumboArriba) }
                VStack(spacing: 0) {
                    cartelVista(r).padding(.horizontal, 12).padding(.top, 10)
                    HStack { Spacer(); botones.padding(.trailing, 12).padding(.top, 14) }
                    Spacer()
                    Text(Estilos.credito(estilo, cat)).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.35)).cornerRadius(4)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10).padding(.bottom, 6)
                    panel(r)
                }
            } else if errorRuta {
                VStack(spacing: 14) {
                    Texto(t("No se ha podido abrir la ruta.", "No s'ha pogut obrir la ruta.", "Couldn't open the route."), 15, .texto)
                    BotonP(t("Volver", "Tornar", "Back"), true) { cerrar() }.frame(width: 200)
                }
            } else { ProgressView() }
            if let a = aviso {
                VStack { Spacer(); Text(a).font(.callout.weight(.semibold)).foregroundColor(.white).multilineTextAlignment(.center)
                    .padding(14).frame(maxWidth: .infinity).background(Color(hex: 0x0B0F15).opacity(0.95)).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borde)).padding(.horizontal, 16).padding(.bottom, 190) }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(false)
        .onAppear {
            if nav.archivo != archivo || !nav.navegando { if !nav.empezar(archivo) { errorRuta = true } }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(nav.objectWillChange) { _ in DispatchQueue.main.async { empujar() } }
        .onChange(of: mapa.listo) { _ in empujar() }
        .sheet(isPresented: $elegirEstilo) { selectorEstilo.preferredColorScheme(.dark) }
        .confirmationDialog("", isPresented: $opciones, titleVisibility: .hidden) {
            Button(t("Ver toda la ruta", "Veure tota la ruta", "Show whole route")) { mapa.js("verTodo()"); mapa.seguir = false }
            Button(t("Estilo del mapa (satélite, topográfico…)", "Estil del mapa (satèl·lit, topogràfic…)", "Map style (satellite, topographic…)")) { elegirEstilo = true }
            Button(t("Guardar el mapa de la ruta para ir sin cobertura", "Desar el mapa de la ruta per anar sense cobertura", "Save the route map for offline use")) { guardarMapa() }
            Button(t("Cambiar de ruta", "Canviar de ruta", "Change route")) { cerrar() }
            Button(t("Cancelar", "Cancel·lar", "Cancel"), role: .cancel) {}
        }
        .alert(t("¿Dejar de navegar?", "Deixar de navegar?", "Stop navigating?"), isPresented: $confirmarParar) {
            Button(t("Parar", "Aturar", "Stop"), role: .destructive) { nav.parar(); cerrar() }
            Button(t("Seguir navegando", "Continuar navegant", "Keep navigating"), role: .cancel) {}
        } message: {
            Text(t("Se paran los avisos de la ruta. La emisión de la prueba sigue: se para desde la prueba.",
                   "S'aturen els avisos de la ruta. L'emissió de la prova continua: s'atura des de la prova.",
                   "Route alerts stop. The event tracking keeps going: stop it from the event screen."))
        }
    }

    /// Envía la posición al mapa.
    private func empujar() {
        guard mapa.listo, let p = nav.pos, nav.archivo == archivo else { return }
        let r = nav.rumbo.isNaN ? "null" : String(format: "%.1f", nav.rumbo)
        mapa.js(String(format: "pos(%.7f,%.7f,%@,%.1f,false)", p.coordinate.longitude, p.coordinate.latitude, r, nav.estuvoEnRuta ? nav.enRuta : -1))
        // incidencias de tráfico de la Ronda (DGT / Trànsit) en el mapa
        if mapa.traficoVersion != TraficoMapa.version || Date().timeIntervalSince(mapa.traficoT) > 30 {
            mapa.traficoVersion = TraficoMapa.version
            mapa.traficoT = Date()
            mapa.js("trafico(" + TraficoMapa.json() + ")")
        }
    }

    private func mostrar(_ s: String) {
        withAnimation { aviso = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { if aviso == s { aviso = nil } } }
    }

    // ---------- cartel ----------
    private struct Cartel { let colIcono: Color, fondo: Color, borde: Color, icono: String, titulo: String, sub: String }

    private func cartelDatos(_ r: Gpx) -> (Cartel, Bool) {
        let azul = Color(hex: 0x2F7DE1), fondo = Color(hex: 0x0B0F15).opacity(240 / 255)
        let kmTot = Rutas.km(r.total / 1000) + " km" + (r.conAltura ? " · +" + Poker.miles(Int(r.subidaTotal.rounded())) + " m" : "")
        guard let p = nav.pos else {
            let sinPermiso = CLLocationManager().authorizationStatus == .denied
            return (Cartel(colIcono: azul, fondo: fondo, borde: .borde, icono: "⌖",
                           titulo: sinPermiso ? t("Sin permiso de ubicación", "Sense permís d'ubicació", "No location permission") : t("Buscando el GPS…", "Buscant el GPS…", "Waiting for GPS…"),
                           sub: guardando ?? kmTot), false)
        }
        let giro = rumboArriba && !nav.rumbo.isNaN ? nav.rumbo : 0
        if nav.llegado {
            return (Cartel(colIcono: Color(hex: 0x3FBF7F), fondo: Color(hex: 0x103422), borde: Color(hex: 0x3FBF7F), icono: "🏁",
                           titulo: t("¡Has llegado!", "Has arribat!", "You've arrived!"), sub: Rutas.km(r.total / 1000) + t(" km de ruta", " km de ruta", " km route")), true)
        }
        if nav.fuera, let c = nav.cercano {
            let rb = Gpx.rumbo(p.coordinate.latitude, p.coordinate.longitude, c.lat, c.lon)
            return (Cartel(colIcono: .rojo, fondo: Color(hex: 0x5A1518), borde: .rojo, icono: "⚠",
                           titulo: t("Te has salido de la ruta", "T'has sortit de la ruta", "You are off the route"),
                           sub: t("A ", "A ", "") + "\(Int(nav.aRuta.rounded())) m · " + t("vuelve hacia el ", "torna cap al ", "head ") + Navegacion.direccion(rb) + " " + Navegacion.flecha(rb - giro)), true)
        }
        if !nav.estuvoEnRuta {
            let rb = nav.cercano.map { Gpx.rumbo(p.coordinate.latitude, p.coordinate.longitude, $0.lat, $0.lon) } ?? 0
            return (Cartel(colIcono: azul, fondo: fondo, borde: .borde, icono: Navegacion.flecha(rb - giro),
                           titulo: t("Ve hacia la ruta", "Ves cap a la ruta", "Head to the route"),
                           sub: guardando ?? (t("Está a ", "És a ", "It is ") + Navegacion.metrosDichos(nav.aRuta) + t(", hacia el ", ", cap al ", " to the ") + Navegacion.direccion(rb))), false)
        }
        let g = nav.proximo
        let d = g.map { $0.d - nav.enRuta } ?? .greatestFiniteMagnitude
        if let g = g, d < 2000 {
            let ic = g.tipo == 3 ? (g.lado < 0 ? "↶" : "↷") : (g.lado < 0 ? "↰" : "↱")
            return (Cartel(colIcono: azul, fondo: fondo, borde: .borde, icono: ic, titulo: Navegacion.textoGiro(g),
                           sub: t("dentro de ", "d'aquí a ", "in ") + Navegacion.metrosDichos(d)), d < 300)
        }
        return (Cartel(colIcono: azul, fondo: fondo, borde: .borde, icono: "↑", titulo: t("Sigue la ruta", "Segueix la ruta", "Follow the route"),
                       sub: guardando ?? (g == nil ? t("Sin curvas fuertes hasta el final", "Sense revolts forts fins al final", "No sharp bends to the end")
                                    : t("Próxima curva fuerte a ", "Proper revolt fort a ", "Next sharp bend in ") + Navegacion.metrosDichos(d))), false)
    }

    @ViewBuilder private func cartelVista(_ r: Gpx) -> some View {
        let (c, importante) = cartelDatos(r)
        let min = cartelMin && !importante
        HStack(spacing: 0) {
            Text(c.icono).font(.system(size: min ? 18 : 24)).foregroundColor(.white)
                .frame(width: min ? 34 : 46, height: min ? 34 : 46).background(RoundedRectangle(cornerRadius: 12).fill(c.colIcono))
            VStack(alignment: .leading, spacing: 1) {
                Text(c.titulo).font(.system(size: min ? 14 : 17, weight: .medium)).foregroundColor(.white).lineLimit(1)
                if !min { Text(c.sub).font(.system(size: 13.5)).foregroundColor(.suave).lineLimit(2) }
            }.padding(.leading, 12)
            Spacer(minLength: 4)
            Button { cerrar() } label: { Text("✕").font(.system(size: 15)).foregroundColor(.suave).frame(width: 34, height: 34) }
                .accessibilityLabel(t("Volver a las rutas", "Tornar a les rutes", "Back to routes"))
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, min ? 6 : 10)
        .background(RoundedRectangle(cornerRadius: 18).fill(c.fondo))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.borde, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        .onTapGesture { cartelMin.toggle() }
    }

    // ---------- botones ----------
    private var botones: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button {
                rumboArriba.toggle(); mapa.seguir = true
                mapa.js("rumboArriba(\(rumboArriba))")
                mostrar(rumboArriba ? t("El mapa gira con tu rumbo", "El mapa gira amb el teu rumb", "Map follows your heading") : t("Norte arriba", "Nord a dalt", "North up"))
            } label: { Brujula(angulo: rumboArriba && !nav.rumbo.isNaN ? -nav.rumbo : 0).modifier(Redondo()) }
                .accessibilityLabel(t("Girar el mapa con el rumbo o con el norte arriba", "Girar el mapa amb el rumb o amb el nord a dalt", "Heading up or north up"))
            Button { mapa.seguir = true; mapa.js("centrar()") } label: {
                Text("◎").font(.system(size: 21)).foregroundColor(mapa.seguir ? .suave : .azul).modifier(Redondo(activo: !mapa.seguir))
            }.accessibilityLabel(t("Centrar en mi posición", "Centrar a la meva posició", "Centre on my position"))
            Button {
                nav.voz.toggle()
                mostrar(nav.voz ? t("Avisos de voz activados", "Avisos de veu activats", "Voice alerts on") : t("Avisos de voz desactivados", "Avisos de veu desactivats", "Voice alerts off"))
            } label: { Text(nav.voz ? "🔊" : "🔇").font(.system(size: 18)).modifier(Redondo()) }
                .accessibilityLabel(nav.voz ? t("Quitar la voz", "Treure la veu", "Mute voice") : t("Poner la voz", "Posar la veu", "Voice on"))
            Button { elegirEstilo = true } label: {
                HStack(spacing: 7) { Image(systemName: "square.3.layers.3d").font(.system(size: 15)); Text(t("Mapa", "Mapa", "Map")).font(.system(size: 13.5, weight: .medium)) }
                    .foregroundColor(.white).padding(.leading, 12).padding(.trailing, 15).frame(height: 48)
                    .background(Capsule().fill(Color(hex: 0x2F7DE1))).overlay(Capsule().stroke(Color(hex: 0x6FB0FF), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
            }.accessibilityLabel(t("Cambiar el estilo del mapa", "Canviar l'estil del mapa", "Change map style"))
            Button { opciones = true } label: { Text("⋯").font(.system(size: 22)).foregroundColor(.texto).modifier(Redondo()) }
                .accessibilityLabel(t("Más opciones", "Més opcions", "More options"))
        }
    }

    // ---------- panel ----------
    @ViewBuilder private func panel(_ r: Gpx) -> some View {
        let enMarcha = nav.pos != nil && nav.archivo == archivo
        let hechos = enMarcha ? nav.enRuta : 0
        let falta = max(0, r.total - hechos)
        let sube = r.conAltura ? "+\(Int(max(0, r.subidaTotal - (enMarcha ? r.subidaEn(nav.enRuta) : 0)).rounded()))" : Rutas.km(r.total / 1000)
        VStack(alignment: .leading, spacing: 0) {
            if panelMin {
                HStack {
                    Text(Rutas.km(falta / 1000) + t(" km faltan", " km falten", " km to go")).font(.custom("TeXGyrePagella-Bold", size: 18)).foregroundColor(Color(hex: 0x7FD3EA))
                    Spacer()
                    Image(systemName: "chevron.up").foregroundColor(.suave)
                }
            } else {
                HStack(spacing: 8) {
                    cifra(Rutas.km(hechos / 1000), t("km hechos", "km fets", "km done"), .texto)
                    cifra(Rutas.km(falta / 1000), t("km faltan", "km falten", "km to go"), Color(hex: 0x7FD3EA))
                    cifra(sube, r.conAltura ? t("m por subir", "m per pujar", "m to climb") : t("km en total", "km en total", "km total"), .texto)
                }
                if r.conAltura { Perfil(ruta: r, donde: nav.estuvoEnRuta && enMarcha ? nav.enRuta : -1).frame(height: 58).padding(.top, 10) }
                if let e = nav.emite {
                    Text("📡  " + t("Emitiendo tu posición en ", "Emetent la teva posició a ", "Sharing your position in ") + e)
                        .font(.system(size: 11.5, weight: .medium)).foregroundColor(Color(hex: 0x3FBF7F)).padding(.top, 8)
                }
                HStack {
                    Text(nav.nombre).font(.system(size: 13)).foregroundColor(.suave).lineLimit(1)
                    Spacer(minLength: 10)
                    Button { confirmarParar = true } label: {
                        Text("■  " + t("Parar", "Aturar", "Stop")).font(.system(size: 14, weight: .medium)).foregroundColor(Color(hex: 0xC9D3DF))
                            .padding(.horizontal, 16).padding(.vertical, 9).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borde))
                    }
                }.padding(.top, 10)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 12)
        .background(LinearGradient(colors: [Color(hex: 0x0B0F15).opacity(215 / 255), Color.fondo], startPoint: .top, endPoint: .bottom)
            .clipShape(RoundedCornerShape(radio: 20)).ignoresSafeArea(edges: .bottom))
        .contentShape(Rectangle())
        .onTapGesture { panelMin.toggle() }
    }

    private func cifra(_ n: String, _ e: String, _ c: Color) -> some View {
        VStack(spacing: 0) {
            Text(n).font(.custom("TeXGyrePagella-Bold", size: 23)).foregroundColor(c).lineLimit(1).minimumScaleFactor(0.6)
            Text(e).font(.system(size: 11)).foregroundColor(.suave)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borde, lineWidth: 1))
    }

    // ---------- estilo del mapa ----------
    private var selectorEstilo: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if nav.navegando { Texto("● " + t("sigues navegando", "continues navegant", "still navigating"), 12, Color(hex: 0x3FBF7F), .medium) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                        ForEach(Estilos.todos, id: \.self) { e in
                            Button {
                                estilo = e
                                UserDefaults.standard.set(e, forKey: "nav_estilo")
                                mapa.js("estilo('\(e)', \(cat))")
                                mapa.seguir = true
                                elegirEstilo = false
                            } label: {
                                VStack(spacing: 4) {
                                    Image(Estilos.miniatura(e)).resizable().scaledToFill().frame(height: 74).clipped().cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(e == estilo ? Color.azul : Color.borde, lineWidth: e == estilo ? 3 : 1))
                                    Text(Estilos.nombre(e)).font(.system(size: 13, weight: .medium)).foregroundColor(.texto)
                                    Text(Estilos.detalle(e)).font(.system(size: 11)).foregroundColor(.suave)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    Button { elegirEstilo = false; guardarMapa() } label: {
                        HStack {
                            Text("⬇").font(.system(size: 18))
                            Text(t("Guardar este mapa de la ruta para ir sin cobertura", "Desar aquest mapa de la ruta per anar sense cobertura", "Save this route map for offline use"))
                                .font(.system(size: 13.5)).foregroundColor(.texto).multilineTextAlignment(.leading)
                            Spacer()
                            Text(t("Guardar", "Desar", "Save")).font(.system(size: 13.5, weight: .medium)).foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(Color.azul))
                        }.padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Color.panel)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borde))
                    }.buttonStyle(.plain)
                }.padding(16)
            }
            .background(Color.fondo.ignoresSafeArea())
            .navigationTitle(t("Estilo del mapa", "Estil del mapa", "Map style")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("Cerrar", "Tancar", "Close")) { elegirEstilo = false } } }
        }
    }

    private func guardarMapa() {
        guard let r = ruta else { return }
        if Estilos.es3d(estilo) {
            mostrar(t("En 3D y en primera persona el mapa necesita cobertura. Para ir sin cobertura, guarda el mapa en satélite, topográfico o relieve.",
                      "En 3D i en primera persona el mapa necessita cobertura. Per anar sense cobertura, desa el mapa en satèl·lit, topogràfic o relleu.",
                      "3D and first-person views need signal. To ride without signal, save the satellite, topographic or relief map."))
            return
        }
        if guardando != nil { mostrar(t("Ya se está guardando…", "Ja s'està desant…", "Already saving…")); return }
        let est = estilo
        guardando = t("Guardando el mapa…", "Desant el mapa…", "Saving map…")
        mostrar(t("Guardando el mapa ", "Desant el mapa ", "Saving the ") + Estilos.nombre(est).lowercased() + t(" de la ruta. Mejor con wifi.", " de la ruta. Millor amb wifi.", " route map. Wi-Fi recommended."))
        Task {
            _ = await Teselas.guardar(r, estilo: est, cat: cat) { h, tot in
                guardando = t("Guardando el mapa… ", "Desant el mapa… ", "Saving map… ") + "\(h)/\(tot)"
            }
            guardando = nil
            mostrar(t("Mapa guardado: la ruta se ve sin cobertura.", "Mapa desat: la ruta es veu sense cobertura.", "Map saved: the route works without signal."))
        }
    }
}

struct Redondo: ViewModifier {
    var activo = false
    func body(content: Content) -> some View {
        content.frame(width: 48, height: 48)
            .background(Circle().fill(activo ? Color(hex: 0x102846).opacity(245 / 255) : Color(hex: 0x0B0F15).opacity(235 / 255)))
            .overlay(Circle().stroke(activo ? Color.azul : Color.borde, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

struct RoundedCornerShape: Shape {
    let radio: CGFloat
    func path(in r: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: r, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: radio, height: radio)).cgPath)
    }
}

/// La brújula: la N apunta al norte del mapa.
struct Brujula: View {
    let angulo: Double
    var body: some View {
        ZStack {
            Path { p in p.move(to: CGPoint(x: 12, y: 2)); p.addLine(to: CGPoint(x: 17, y: 12)); p.addLine(to: CGPoint(x: 7, y: 12)); p.closeSubpath() }.fill(Color.rojo)
            Path { p in p.move(to: CGPoint(x: 12, y: 22)); p.addLine(to: CGPoint(x: 17, y: 12)); p.addLine(to: CGPoint(x: 7, y: 12)); p.closeSubpath() }.fill(Color.suave)
        }
        .frame(width: 24, height: 24).rotationEffect(.degrees(angulo))
    }
}

/// El perfil de altura de la ruta, con lo hecho más oscuro y una marca donde estás.
struct Perfil: View {
    let ruta: Gpx
    let donde: Double
    var body: some View {
        Canvas { cx, size in
            let n = 120, tot = max(1, ruta.total)
            let alts = (0...n).map { ruta.alturaEn(tot * Double($0) / Double(n)) }
            let mn = alts.min() ?? 0, mx = max((alts.max() ?? 1), mn + 30)
            func pt(_ i: Int) -> CGPoint { CGPoint(x: size.width * CGFloat(i) / CGFloat(n), y: size.height - 4 - (size.height - 8) * CGFloat((alts[i] - mn) / (mx - mn))) }
            var area = Path(); area.move(to: CGPoint(x: 0, y: size.height))
            for i in 0...n { area.addLine(to: pt(i)) }
            area.addLine(to: CGPoint(x: size.width, y: size.height)); area.closeSubpath()
            cx.fill(area, with: .linearGradient(Gradient(colors: [Color(hex: 0x3AA6FF).opacity(0.55), Color(hex: 0x3AA6FF).opacity(0.08)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            var linea = Path(); linea.move(to: pt(0))
            for i in 1...n { linea.addLine(to: pt(i)) }
            cx.stroke(linea, with: .color(Color(hex: 0x7FD3EA)), lineWidth: 1.6)
            if donde >= 0 {
                let x = size.width * CGFloat(min(1, donde / tot))
                cx.fill(Path(CGRect(x: 0, y: 0, width: x, height: size.height)), with: .color(Color.black.opacity(0.35)))
                cx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(.white), lineWidth: 2)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.panel.opacity(0.6)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// El mapa (página mapa.html con MapLibre) dentro de la app.
@MainActor
final class MapaWeb: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var listo = false
    @Published var seguir = true
    @Published var fallo = ""
    var traficoVersion = -1
    var traficoT = Date.distantPast
    let web: WKWebView
    private var inicio: String? = nil

    override init() {
        let c = WKWebViewConfiguration()
        c.setURLSchemeHandler(Teselas.shared, forURLScheme: "tesela")
        web = WKWebView(frame: .zero, configuration: c)
        super.init()
        web.configuration.userContentController.add(self, name: "Nav")
        web.isOpaque = false
        web.backgroundColor = UIColor(Color(hex: 0x1A2230))
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = self
    }

    func iniciar(_ r: Gpx, estilo: String, cat: Bool, rumboArriba: Bool) {
        guard inicio == nil else { return }
        let idx = r.simplificar(4)
        let coords = "[" + idx.map { String(format: "[%.6f,%.6f]", r.lon[$0], r.lat[$0]) }.joined(separator: ",") + "]"
        let pasos = "[" + r.pasos.map { p in
            let n = p.nombre.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "'")
            return String(format: "{\"lat\":%.6f,\"lon\":%.6f,\"n\":\"%@\"}", p.lat, p.lon, n)
        }.joined(separator: ",") + "]"
        inicio = "iniciar(\(coords), \(pasos), '\(estilo)', \(cat), \(rumboArriba))"
        if let u = Bundle.main.url(forResource: "mapa", withExtension: "html") {
            web.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent())
        }
    }

    func js(_ s: String) { web.evaluateJavaScript(s, completionHandler: nil) }

    nonisolated func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        let q = m.body as? String
        Task { @MainActor in
            if q == "listo" { self.listo = true }
            if q == "movido" { self.seguir = false }
            if let q = q, q.hasPrefix("error:") { NSLog("[mapa] %@", q); if self.fallo.isEmpty { self.fallo = q } }
        }
    }
}

extension MapaWeb: WKNavigationDelegate {
    nonisolated func webView(_ w: WKWebView, didFail navigation: WKNavigation!, withError e: Error) {
        Task { @MainActor in self.fallo = "error:carga " + e.localizedDescription }
    }
    nonisolated func webView(_ w: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError e: Error) {
        Task { @MainActor in self.fallo = "error:carga " + e.localizedDescription }
    }
    nonisolated func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            if let i = self.inicio {
                self.web.evaluateJavaScript(i) { _, e in
                    if let e = e { Task { @MainActor in self.fallo = "error:iniciar " + String(describing: e).prefix(300) } }
                }
            }
        }
    }
}

struct MapaVista: UIViewRepresentable {
    let mapa: MapaWeb
    func makeUIView(context: Context) -> WKWebView { mapa.web }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
