import SwiftUI
import CoreLocation
import WebKit

/// Pantalla de inicio, igual que la de Android 1.57: reloj a la décima y banderitas, aviso de los relojes atómicos,
/// cronómetro, «ONE SECOND», la Ronda destacada, el Navigator, una banda metálica por prueba (con su logo, «ⓘ Info»,
/// luz de VINCULADA / EMITIENDO y tira de INSCRIPCIONES ABIERTAS), la cuenta One Second y los avisos de las pruebas.
struct SelectorView: View {
    @EnvironmentObject var central: Central
    @EnvironmentObject var cuenta: Cuenta
    @Binding var abierta: Prueba?
    @Binding var navAbierto: Bool
    @State private var hoja: Hoja? = nil
    @State private var elegir: [Cuenta.Insc] = []
    @State private var mensaje: (String, String)? = nil
    @State private var poker: PruebaWeb? = nil
    @AppStorage("navigator_visto") private var navVisto = false

    enum Hoja: Identifiable {
        case info(String, String, String, [UInt32]), entrar, web(String), navigator
        var id: String {
            switch self {
            case .info(let i, _, _, _): return "info_" + i
            case .entrar: return "entrar"
            case .web(let u): return "web_" + u
            case .navigator: return "navigator"
            }
        }
    }

    private static let navMetal: [UInt32] = [0x0A2A3A, 0x2F8FA8, 0x123C55]

    var body: some View {
        let _ = central.tick
        let alto: CGFloat = (2 + Prueba.todas.count + PruebaWeb.todas.count) > 4 ? 78 : 108
        NavigationView {
            ZStack {
                Color.fondo.ignoresSafeArea()
                ForEach(Prueba.todas) { p in
                    NavigationLink(tag: p, selection: $abierta) { PruebaView(p: p) } label: { EmptyView() }.hidden()
                }
                NavigationLink(isActive: $navAbierto) { NavigatorView() } label: { EmptyView() }.hidden()
                ForEach(PruebaWeb.todas) { w in
                    NavigationLink(tag: w, selection: $poker) { PokerView(d: w) } label: { EmptyView() }.hidden()
                }
                ScrollView {
                    VStack(spacing: 0) {
                        HStack(spacing: 2) {
                            RelojGPSView()
                            Spacer(minLength: 4)
                            ForEach(0..<3) { i in Bandera(idioma: i) { Idioma.elegido = i; central.tick += 1; cuenta.programarAvisos() } }
                        }
                        relojesAtomicos.padding(.top, 8)
                        Image("cronometro").resizable().scaledToFit().frame(width: 84).padding(.top, 10)
                        Text("ONE SECOND").font(.custom("TeXGyrePagella-Bold", size: 27)).tracking(27 * 0.14)
                            .foregroundColor(Color(hex: 0xE9EEF5)).padding(.top, 6)
                        Text(t("ELIGE TU PRUEBA", "TRIA LA TEVA PROVA", "CHOOSE YOUR EVENT")).font(.system(size: 10, weight: .medium))
                            .tracking(2).foregroundColor(.suave).padding(.top, 2)

                        VStack(spacing: 12) {
                            rondaDestacada.padding(.bottom, 2)
                            Banda(id: "navigator", nombre: "One Second Navigator",
                                  sub: t("Navega con las rutas GPX", "Navega amb les rutes GPX", "Navigate GPX routes"),
                                  icono: "ic_navigator", metal: SelectorView.navMetal, alto: alto, nuevo: !navVisto,
                                  abrir: { navVisto = true; navAbierto = true },
                                  info: { hoja = .info("navigator", "One Second Navigator", "ic_navigator", SelectorView.navMetal) })
                            ForEach(Prueba.todas.filter { $0.id != "ronda" }) { p in
                                let aj = central.aj(p)
                                Banda(id: p.id, nombre: p.nombre, sub: aj.vinculada ? aj.piloto : p.subtitulo, icono: p.icono, metal: p.metal, alto: alto,
                                      vinc: aj.vinculada, emi: central.emitiendo(p), abierta: cuenta.abiertas.contains(p.appCuentas),
                                      abrir: { abierta = p }, info: { hoja = .info(p.id, p.nombre, p.icono, p.metal) })
                            }
                            NavigationLink(isActive: $navAbierto) { NavigatorView() } label: { EmptyView() }.hidden()
                ForEach(PruebaWeb.todas) { w in
                                Banda(id: w.id, nombre: w.nombre, sub: w.subtitulo, icono: w.icono, metal: w.metal, alto: alto,
                                      abierta: cuenta.abiertas.contains(w.id),
                                      abrir: { poker = w }, info: { hoja = .info(w.id, w.nombre, w.icono, w.metal) })
                            }
                        }.padding(.top, 20)

                        cajaCuenta.padding(.top, 16)
                        filaAvisos.padding(.top, 12)
                        Text("onesecond.es · v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                            .font(.system(size: 11)).foregroundColor(Color(hex: 0x5F6B7D)).padding(.top, 18)
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
                }
                Breve()
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .sheet(item: $hoja) { h in
            Group {
                switch h {
                case .info(let id, let n, let ic, let m): InfoView(id: id, nombre: n, icono: ic, metal: m)
                case .entrar: EntrarView()
                case .web(let u): WebCuentaView(url: u)
                case .navigator: NavigatorPronto()
                }
            }
            .environmentObject(central).environmentObject(cuenta).preferredColorScheme(.dark)
        }
        .confirmationDialog(t("¿Con qué inscripción vinculas la app?", "Amb quina inscripció vincules l'app?", "Which registration do you link?"),
                            isPresented: Binding(get: { !elegir.isEmpty }, set: { if !$0 { elegir = [] } }), titleVisibility: .visible) {
            ForEach(elegir) { x in
                Button(x.evento + (x.dorsal.isEmpty ? "" : " · " + t("dorsal ", "dorsal ", "no. ") + x.dorsal)) { vincular(x) }
            }
            Button(t("Cancelar", "Cancel·lar", "Cancel"), role: .cancel) { for x in elegir { cuenta.marcarVista(x.url) } }
        }
        .alert(mensaje?.0 ?? "", isPresented: Binding(get: { mensaje != nil }, set: { if !$0 { mensaje = nil } })) {
            Button("OK") {}
        } message: { Text(mensaje?.1 ?? "") }
        .onAppear {
            if Demo.activo, Demo.pantalla >= 6, Demo.pantalla - 6 < PruebaWeb.todas.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poker = PruebaWeb.todas[Demo.pantalla - 6] }
            }
            if Demo.activo, Demo.pantalla == 9 || Demo.pantalla == 10 {
                let a = Demo.pantalla == 10 ? Navegacion.shared.cargarDemo() : nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { navAbierto = true }
                if let a = a { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NotificationCenter.default.post(name: .gpxRecibido, object: a) } }
            }
        }
        .task {
            if Demo.activo { return }
            await cuenta.actualizar()
            let n = await cuenta.nuevasParaVincular(central)
            if n.count == 1 { vincular(n[0]) } else if n.count > 1 { elegir = n }
        }
    }

    // ---------- piezas ----------
    private var relojesAtomicos: some View {
        HStack(spacing: 10) {
            Text("🛰").font(.system(size: 15))
            Text(t("El tiempo se toma de los relojes atómicos de los satélites, a través del GPS",
                   "El temps es pren dels rellotges atòmics dels satèl·lits, a través del GPS",
                   "Time is taken from the satellites' atomic clocks, via GPS"))
                .font(.system(size: 11.5)).foregroundColor(Color(hex: 0xC9D3DF)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 61 / 255, green: 1, blue: 138 / 255).opacity(20 / 255)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 61 / 255, green: 1, blue: 138 / 255).opacity(90 / 255), lineWidth: 1))
    }

    /// La Ronda, la primera y destacada: nombre, día y lugar de la próxima Ronda y, debajo, vincular / dorsal / emitiendo.
    private var rondaDestacada: some View {
        let p = Prueba.ronda
        let aj = central.aj(p), vinc = aj.vinculada, emi = central.emitiendo(p)
        return Button { abierta = p } label: {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(p.icono).resizable().scaledToFill().frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.nombre).font(.custom("TeXGyrePagella-Bold", size: 22)).foregroundColor(.white).shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                        Text(cuenta.proximaRonda ?? p.subtitulo).font(.system(size: 12.5)).foregroundColor(.white.opacity(225 / 255))
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Text(emi ? "📡  " + t("Emitiendo tu posición", "Emetent la teva posició", "Sharing your position")
                         : vinc ? "✓  " + aj.piloto
                         : "🔗  " + t("Toca para vincular tu dorsal", "Toca per vincular el teu dorsal", "Tap to link your race number"))
                        .font(.system(size: 13.5, weight: .medium)).foregroundColor(.white).lineLimit(1)
                    Spacer()
                    Text("›").font(.system(size: 20)).foregroundColor(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(72 / 255)))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(LinearGradient(colors: p.metal.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(hex: 0xF0C9A8), lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var cajaCuenta: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(cuenta.conectado ? t("CUENTA ONE SECOND", "COMPTE ONE SECOND", "ONE SECOND ACCOUNT") : t("¿YA TE HAS INSCRITO?", "JA T'HAS INSCRIT?", "ALREADY REGISTERED?"))
                .font(.system(size: 10, weight: .medium)).tracking(1.6).foregroundColor(.oroCuenta)
            Text(cuenta.conectado ? cuenta.email : t("Entra con tu cuenta de onesecond.es y la app se vincula sola con tu inscripción.",
                                                      "Entra amb el teu compte d'onesecond.es i l'app es vincula sola amb la teva inscripció.",
                                                      "Sign in with your onesecond.es account and the app links itself to your registration."))
                .font(.system(size: 13.5)).foregroundColor(.texto).padding(.top, 4)
            if cuenta.conectado {
                HStack(spacing: 8) {
                    BotonCuenta(texto: t("Mi cuenta", "El meu compte", "My account"), principal: true) { hoja = .web(Cuenta.base + "/?lang=" + Idioma.codigo) }
                    BotonCuenta(texto: t("Inscribirme", "Inscriure'm", "Register"), principal: true) { hoja = .web(Cuenta.base + "/?lang=" + Idioma.codigo + "#eventos") }
                }.padding(.top, 12)
                HStack(spacing: 8) {
                    BotonCuenta(texto: t("Vincular mi inscripción", "Vincular la meva inscripció", "Link my registration"), principal: false) { buscarInscripciones() }
                    BotonCuenta(texto: t("Salir", "Sortir", "Sign out"), principal: false, ancho: false) { cuenta.salir() }
                }.padding(.top, 8)
            } else {
                BotonCuenta(texto: t("Entrar con mi cuenta", "Entrar amb el meu compte", "Sign in"), principal: true) { hoja = .entrar }.padding(.top, 12)
                BotonCuenta(texto: t("Crear cuenta nueva", "Crear un compte nou", "Create a new account"), principal: false, color: .oroCuenta) {
                    hoja = .web(Cuenta.base + "/registro?lang=" + Idioma.codigo)
                }.padding(.top, 8)
                Text(t("¿Aún no tienes cuenta? Es gratis y sirve también en la web.", "Encara no tens compte? És gratuït i serveix també a la web.", "No account yet? It's free and also works on the website."))
                    .font(.system(size: 12)).foregroundColor(Color(hex: 0xA3AFC0)).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 6)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borde, lineWidth: 1))
    }

    private var filaAvisos: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("🔔  " + t("Avisos de las pruebas", "Avisos de les proves", "Event reminders")).font(.system(size: 14.5, weight: .medium)).foregroundColor(.texto)
                Text(t("Unos días antes de las pruebas con telemetría gratuita en las que aún puedes inscribirte, y la mañana de la prueba.",
                       "Uns dies abans de les proves amb telemetria gratuïta on encara et pots inscriure, i el matí de la prova.",
                       "A few days before events with free telemetry you can still sign up for, and on the morning of the event."))
                    .font(.system(size: 12)).foregroundColor(.suave)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { cuenta.avisosActivos }, set: { v in cuenta.avisosActivos = v; if v { Notificar.pedirPermiso() } }))
                .labelsHidden()
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borde, lineWidth: 1))
    }

    // ---------- acciones ----------
    private func buscarInscripciones() {
        Task {
            guard let l = await cuenta.misInscripciones() else {
                mensaje = (t("No se pudo conectar", "No s'ha pogut connectar", "Could not connect"),
                           t("Comprueba la conexión y vuelve a intentarlo.", "Comprova la connexió i torna-ho a provar.", "Check your connection and try again."))
                return
            }
            if l.isEmpty {
                mensaje = (t("No hay inscripciones con app", "No hi ha inscripcions amb app", "No registrations with the app"),
                           t("No tienes ninguna inscripción pagada de One Second Rally, Rally Poker o Ronda la Llana de hoy en adelante.",
                             "No tens cap inscripció pagada de One Second Rally, Rally Poker o Ronda la Llana d'avui endavant.",
                             "You have no paid One Second Rally, Rally Poker or Ronda la Llana registration from today onwards."))
            } else if l.count == 1 { vincular(l[0]) } else { elegir = l }
        }
    }

    private func vincular(_ x: Cuenta.Insc) {
        cuenta.marcarVista(x.url)
        elegir = []
        if let e = central.vincular(x.prueba, url: x.url) { central.breve(e, error: true); return }
        central.breve(t("Vinculada con tu inscripción ✓", "Vinculada amb la teva inscripció ✓", "Linked to your entry ✓"))
        abierta = x.prueba
    }
}

/// Banda metálica de una prueba (como Selector.banda de Android).
struct Banda: View {
    let id: String, nombre: String, sub: String, icono: String, metal: [UInt32]
    let alto: CGFloat
    var vinc = false, emi = false, abierta = false, nuevo = false
    let abrir: () -> Void
    let info: () -> Void
    @State private var late = false

    var body: some View {
        let grande = alto > 90
        let col: Color = emi ? .rojo : .verde
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: metal.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
            // logo de la prueba, grande y girado, asomando por la derecha
            Image(icono).resizable().scaledToFit().frame(width: alto + 12, height: alto + 12).rotationEffect(.degrees(-8))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: grande ? 22 : 8, y: grande ? -14 : -8)
            // nombre y debajo el subtítulo (o el dorsal y el nombre del piloto si está vinculada)
            VStack(alignment: .leading, spacing: 1) {
                Spacer(minLength: 0)
                Text(nombre).font(.custom("TeXGyrePagella-Bold", size: grande ? 21 : nombre.count > 18 ? 17 : 19)).tracking(0.5)
                    .foregroundColor(.white).shadow(color: .black.opacity(0.67), radius: 4, y: 1).lineLimit(1).minimumScaleFactor(0.8)
                if !abierta {
                    Text(sub).font(.system(size: 12)).foregroundColor(.white.opacity(205 / 255)).shadow(color: .black.opacity(0.6), radius: 3, y: 1).lineLimit(1)
                }
            }
            .padding(.leading, 16).padding(.trailing, grande ? 96 : 70).padding(.bottom, abierta ? (grande ? 30 : 23) : (grande ? 14 : 10))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            if abierta {
                Text("✎  " + t("INSCRIPCIONES ABIERTAS", "INSCRIPCIONS OBERTES", "REGISTRATION OPEN"))
                    .font(.system(size: 9.5, weight: .medium)).tracking(0.7).foregroundColor(Color(hex: 0x1B1400)).lineLimit(1)
                    .padding(.leading, 16).frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
                    .background(Color(hex: 0xFFD257).opacity(235 / 255))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if vinc || emi {
                HStack(spacing: 7) {
                    Circle().fill(col).frame(width: 11, height: 11).overlay(Circle().stroke(col.opacity(0.35), lineWidth: 2))
                        .opacity(late ? (emi ? 0.3 : 0.55) : 1)
                    Text(emi ? t("EMITIENDO", "EMETENT", "LIVE") : t("VINCULADA", "VINCULADA", "LINKED"))
                        .font(.system(size: 10.5, weight: .medium)).tracking(0.8).foregroundColor(.white)
                }
                .padding(.leading, 7).padding(.trailing, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(115 / 255)))
                .padding(.leading, 14).padding(.top, grande ? 12 : 8)
                .onAppear { withAnimation(.easeInOut(duration: emi ? 0.6 : 1.4).repeatForever(autoreverses: true)) { late = true } }
            } else if nuevo {
                Text(t("NUEVO", "NOU", "NEW")).font(.system(size: 10, weight: .medium)).tracking(0.8).foregroundColor(Color(hex: 0x1B1400))
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color(hex: 0xFFD257)))
                    .padding(.leading, 14).padding(.top, grande ? 12 : 8)
            }
        }
        .frame(height: alto)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(vinc || emi ? col : .clear, lineWidth: 2.5))
        .shadow(color: .black.opacity(vinc || emi ? 0.45 : 0), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture(perform: abrir)
        // «ⓘ Info»: qué es la prueba y qué se hace con la app
        .overlay(alignment: .topTrailing) {
            Button(action: info) {
                Text("ⓘ  Info").font(.system(size: 11.5, weight: .medium)).foregroundColor(.white)
                    .padding(.leading, 10).padding(.trailing, 11).padding(.top, 4).padding(.bottom, 5)
                    .background(Capsule().fill(Color.black.opacity(120 / 255)))
                    .overlay(Capsule().stroke(Color.white.opacity(110 / 255), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.trailing, grande ? 100 : 76).padding(.top, grande ? 12 : 8)
        }
        .accessibilityLabel(nombre + (abierta ? ". " + t("Inscripciones abiertas", "Inscripcions obertes", "Registration open") : ""))
    }
}

struct BotonCuenta: View {
    let texto: String
    let principal: Bool
    var color: Color? = nil
    var ancho = true
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Text(texto).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                .foregroundColor(principal ? .white : (color ?? Color(hex: 0xC9D3DF)))
                .padding(.horizontal, 14).padding(.vertical, 11)
                .frame(maxWidth: ancho ? .infinity : nil)
                .background(RoundedRectangle(cornerRadius: 12).fill(principal ? Color.azul : .clear))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(principal ? .clear : (color ?? .borde), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: !ancho, vertical: false)
    }
}

/// Banderita de idioma (España, senyera, Reino Unido) con su código; la elegida, encendida y con borde.
struct Bandera: View {
    let idioma: Int
    let elegir: () -> Void
    var body: some View {
        let activa = Idioma.actual == idioma
        Button(action: elegir) {
            HStack(spacing: 6) {
                Canvas { cx, size in
                    let w = size.width, h = size.height
                    func rect(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat, _ c: Color) { cx.fill(Path(CGRect(x: x, y: y, width: ww, height: hh)), with: .color(c)) }
                    if idioma == 2 {
                        rect(0, 0, w, h, Color(red: 1 / 255, green: 33 / 255, blue: 105 / 255))
                        var d = Path(); d.move(to: .zero); d.addLine(to: CGPoint(x: w, y: h)); d.move(to: CGPoint(x: w, y: 0)); d.addLine(to: CGPoint(x: 0, y: h))
                        cx.stroke(d, with: .color(.white), lineWidth: h * 0.2)
                        cx.stroke(d, with: .color(Color(red: 200 / 255, green: 16 / 255, blue: 46 / 255)), lineWidth: h * 0.08)
                        rect(w * 0.4, 0, w * 0.2, h, .white); rect(0, h / 3, w, h / 3, .white)
                        let rojo = Color(red: 200 / 255, green: 16 / 255, blue: 46 / 255)
                        rect(w * 0.44, 0, w * 0.12, h, rojo); rect(0, h * 0.4, w, h * 0.2, rojo)
                    } else if idioma == 0 {
                        rect(0, 0, w, h, Color(red: 1, green: 196 / 255, blue: 0))
                        let rojo = Color(red: 198 / 255, green: 11 / 255, blue: 30 / 255)
                        rect(0, 0, w, h / 4, rojo); rect(0, h * 3 / 4, w, h / 4, rojo)
                    } else {
                        rect(0, 0, w, h, Color(red: 252 / 255, green: 221 / 255, blue: 9 / 255))
                        for i in 0..<4 { rect(0, h * CGFloat(2 * i + 1) / 9, w, h / 9, Color(red: 218 / 255, green: 18 / 255, blue: 26 / 255)) }
                    }
                }
                .frame(width: 33, height: 22).clipShape(RoundedRectangle(cornerRadius: 4))
                Text(["ES", "CA", "EN"][idioma]).font(.system(size: 12, weight: .medium)).foregroundColor(.white)
            }
            .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 9).frame(minHeight: 44)
            .background(Capsule().fill(activa ? Color.white.opacity(31 / 255) : .clear))
            .overlay(Capsule().stroke(activa ? Color.white.opacity(140 / 255) : .clear, lineWidth: 1))
            .opacity(activa ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel([t("Castellano", "Castellà", "Spanish"), t("Catalán", "Català", "Catalan"), t("Inglés", "Anglès", "English")][idioma])
    }
}

/// Reloj a la décima. Con GPS, la hora de los satélites (relojes atómicos): desfase = hora del GPS − hora del
/// teléfono en el mismo instante. Las décimas se truncan (no se redondean).
final class RelojGPS: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var texto = "--:--:--.-"
    private let lm = CLLocationManager()
    private var desfase: TimeInterval? = nil
    private var timer: Timer?

    func empezar() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.pintar() }
        lm.delegate = self
        let a = lm.authorizationStatus
        if a == .authorizedWhenInUse || a == .authorizedAlways { lm.desiredAccuracy = kCLLocationAccuracyBest; lm.startUpdatingLocation() }
    }
    func parar() { timer?.invalidate(); timer = nil; lm.stopUpdatingLocation() }

    private func pintar() {
        let ahora = Date().addingTimeInterval(desfase ?? 0)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let c = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: ahora)
        let dec = (c.nanosecond ?? 0) / 100_000_000
        texto = String(format: "%02d:%02d:%02d.%d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0, dec)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0, abs(l.timestamp.timeIntervalSinceNow) < 5 else { return }
        desfase = l.timestamp.timeIntervalSince(Date()) + 0     // iOS da la hora de cada posición con la del GPS
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { desfase = nil }
}

struct RelojGPSView: View {
    @StateObject private var r = RelojGPS()
    var body: some View {
        Text(r.texto).font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: 0xC9D3DF))
            .onAppear { r.empezar() }.onDisappear { r.parar() }
    }
}

/// Ventana «ⓘ Info» de una prueba.
struct InfoView: View {
    @Environment(\.dismiss) var cerrar
    let id: String, nombre: String, icono: String, metal: [UInt32]
    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(icono).resizable().scaledToFit().frame(width: 64, height: 64)
                        Text(nombre).font(.custom("TeXGyrePagella-Bold", size: 22)).foregroundColor(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(LinearGradient(colors: metal.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    Text(InfoTextos.texto(id) ?? "").font(.system(size: 15)).foregroundColor(.texto).fixedSize(horizontal: false, vertical: true)
                    BotonCuenta(texto: t("Cerrar", "Tancar", "Close"), principal: true) { cerrar() }
                }.padding(18)
            }
        }
    }
}

/// Entrar con la cuenta One Second (el mismo correo y contraseña de onesecond.es).
struct EntrarView: View {
    @Environment(\.dismiss) var cerrar
    @EnvironmentObject var cuenta: Cuenta
    @State private var email = ""
    @State private var clave = ""
    @State private var ver = false
    @State private var ayuda = ""
    @State private var entrando = false
    var body: some View {
        NavigationView {
            ZStack {
                Color.fondo.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    BotonesSociales(ayuda: $ayuda, entrando: $entrando) { cerrar() }
                    Text(t("o con tu correo", "o amb el teu correu", "or with your email")).font(.footnote).foregroundColor(.suave)
                        .frame(maxWidth: .infinity)
                    TextField(t("Correo electrónico", "Correu electrònic", "Email"), text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).disableAutocorrection(true).textContentType(.username)
                        .padding(12).background(Color.panel).cornerRadius(10).foregroundColor(.white)
                    Group {
                        if ver { TextField(t("Contraseña", "Contrasenya", "Password"), text: $clave) }
                        else { SecureField(t("Contraseña", "Contrasenya", "Password"), text: $clave) }
                    }
                    .textInputAutocapitalization(.never).disableAutocorrection(true).textContentType(.password)
                    .padding(12).background(Color.panel).cornerRadius(10).foregroundColor(.white)
                    Toggle(t("Mostrar la contraseña", "Mostrar la contrasenya", "Show password"), isOn: $ver).foregroundColor(.suave)
                    Text(ayuda.isEmpty ? t("La misma cuenta de onesecond.es.", "El mateix compte d'onesecond.es.", "Your onesecond.es account.") : ayuda)
                        .font(.footnote).foregroundColor(ayuda.isEmpty || entrando ? .suave : .rojo)
                    BotonCuenta(texto: entrando ? t("Entrando…", "Entrant…", "Signing in…") : t("Entrar", "Entrar", "Sign in"), principal: true) { entrar() }
                        .disabled(entrando)
                    Spacer()
                }.padding(18)
            }
            .navigationTitle(t("Entrar con tu cuenta One Second", "Entra amb el teu compte One Second", "Sign in with your One Second account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Cancelar", "Cancel·lar", "Cancel")) { cerrar() } } }
        }
    }
    private func entrar() {
        let e = email.trimmingCharacters(in: .whitespaces)
        if e.isEmpty || clave.isEmpty { ayuda = t("Escribe tu correo y tu contraseña.", "Escriu el teu correu i la contrasenya.", "Enter your email and password."); return }
        entrando = true; ayuda = t("Entrando…", "Entrant…", "Signing in…")
        Task {
            let err = await cuenta.entrar(email: e, clave: clave)
            entrando = false
            if let err = err { ayuda = err } else { cerrar() }
        }
    }
}

/// «Mi cuenta», «Inscribirme», «Crear cuenta» y las pruebas de póker: la web de One Second dentro de la app,
/// con la misma sesión que la app (para no tener que entrar dos veces).
struct WebCuentaView: View {
    @Environment(\.dismiss) var cerrar
    @EnvironmentObject var cuenta: Cuenta
    let url: String
    var body: some View {
        NavigationView {
            Web(url: url, token: cuenta.token)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("onesecond.es").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("Cerrar", "Tancar", "Close")) { cerrar() } } }
        }
        .onDisappear { Task { await cuenta.actualizar() } }
    }
}

struct Web: UIViewRepresentable {
    let url: String
    let token: String
    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.isOpaque = false
        w.backgroundColor = UIColor(Color.fondo)
        let cargar = { if let u = URL(string: url) { w.load(URLRequest(url: u)) } }
        if !token.isEmpty, let c = HTTPCookie(properties: [.domain: "onesecond.es", .path: "/", .name: Cuenta.cookie, .value: token, .secure: "TRUE"]) {
            w.configuration.websiteDataStore.httpCookieStore.setCookie(c) { cargar() }
        } else { cargar() }
        return w
    }
    func updateUIView(_ v: WKWebView, context: Context) {}
}

/// One Second Navigator: de momento en iPhone, su explicación y aviso de que llega pronto.
struct NavigatorPronto: View {
    @Environment(\.dismiss) var cerrar
    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image("ic_navigator").resizable().scaledToFit().frame(width: 64, height: 64)
                        Text("One Second Navigator").font(.custom("TeXGyrePagella-Bold", size: 22)).foregroundColor(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(LinearGradient(colors: [0x0A2A3A, 0x2F8FA8, 0x123C55].map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    Text(t("Próximamente en iPhone.", "Aviat a l'iPhone.", "Coming soon on iPhone.")).font(.headline).foregroundColor(.oroCuenta)
                    Text(InfoTextos.texto("navigator") ?? "").font(.system(size: 15)).foregroundColor(.texto).fixedSize(horizontal: false, vertical: true)
                    BotonCuenta(texto: t("Cerrar", "Tancar", "Close"), principal: true) { cerrar() }
                }.padding(18)
            }
        }
    }
}

/// Mensajes breves abajo (QR leído, errores...).
struct Breve: View {
    @EnvironmentObject var central: Central
    var body: some View {
        VStack {
            Spacer()
            if let m = central.mensajeBreve {
                Text(m.0).font(.callout.weight(.semibold)).foregroundColor(.white).multilineTextAlignment(.center)
                    .padding(14).frame(maxWidth: .infinity)
                    .background(m.1 ? Color.rojo : Color(hex: 0x2ECC71).opacity(0.9)).cornerRadius(12)
                    .padding(16).transition(.move(edge: .bottom))
            }
        }.animation(.easeInOut, value: central.mensajeBreve?.0)
    }
}
