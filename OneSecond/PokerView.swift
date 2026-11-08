import SwiftUI

/// Rally Poker, Poker Run y Hold'em Run (como Prueba.java de Android 1.57): próximos eventos (inscribirse y pagar),
/// mis inscripciones y resultados, el día de la prueba (Rally Poker va con el GPS de One Second Rally), la clasificación
/// en directo (los 25 primeros, se refresca cada 30 s; en Rally Poker también por tiempos) y la ficha de cada participante.
@MainActor
final class PokerModelo: ObservableObject {
    let d: PruebaWeb
    @Published var cargando = true
    @Published var sinRed = false
    @Published var eventos: [[String: Any]] = []
    @Published var mias: [[String: Any]] = []
    @Published var conectado = false
    @Published var pagoTarjeta = false
    @Published var clas: [String: Any]? = nil
    @Published var clasCod = 0
    @Published var tiempos: [String: Any]? = nil
    @Published var tiemposCod = 0
    @Published var ocupado = false
    var misDorsales: [String] = []
    var misEventos: [String] = []

    init(_ d: PruebaWeb) { self.d = d }

    func cargar() async {
        cargando = true
        let tok = Cuenta.shared.token
        async let ev = Cuenta.pedir("GET", "/api/eventos?app=" + d.id)
        async let cf = Cuenta.pedir("GET", "/api/config")
        let mi: Cuenta.Resp? = tok.isEmpty ? nil : await Cuenta.pedir("GET", "/api/mis_inscripciones", token: tok)
        let (e, c) = await (ev, cf)
        if mi?.codigo == 401 { Cuenta.shared.salir() }
        cargando = false
        sinRed = e.codigo != 200
        guard !sinRed else { return }
        pagoTarjeta = c.json.bool("pago_tarjeta")
        // los eventos desactivados (inscripciones cerradas) no salen, igual que en la web
        eventos = (e.json["eventos"] as? [[String: Any]] ?? []).filter { $0["abierto"] == nil || $0.bool("abierto", true) }
        conectado = Cuenta.shared.conectado && mi?.codigo == 200
        mias = conectado ? (mi!.json["inscripciones"] as? [[String: Any]] ?? []).filter {
            ($0["evento"] as? [String: Any])?.str("app") == d.id && $0.str("estado") != "cancelada" } : []
        misDorsales = []; misEventos = []
        for i in mias where (i.str("tipo").isEmpty ? "piloto" : i.str("tipo")) == "piloto" && i.str("estado") == "pagada" {
            misDorsales.append(PokerModelo.sinCeros(i.str("dorsal_txt")))
            misEventos.append(((i["evento"] as? [String: Any])?.str("nombre") ?? "").trimmingCharacters(in: .whitespaces).lowercased())
        }
        await cargarClas()
    }

    static func sinCeros(_ s: String) -> String { s.replacingOccurrences(of: "^0+(?=\\d)", with: "", options: .regularExpression) }

    /// Un número fijo por móvil para que la web cuente bien a la gente que mira.
    private var idVisita: String {
        if let v = UserDefaults.standard.string(forKey: "prueba_web_vid") { return v }
        let v = "app" + String(UInt64.random(in: 0...UInt64.max), radix: 36)
        UserDefaults.standard.set(v, forKey: "prueba_web_vid")
        return v
    }

    func cargarClas() async {
        let base = "https://onesecond.es" + d.web
        let (c, data) = await Red.pedir(base + "api/web/estado?v=" + idVisita)
        clasCod = c
        let j = Red.objeto(data)
        if c == 200, j["clasificacion"] is [Any], !j.bool("lleno") { clas = j }
        else if c == 503 || j.bool("lleno") { clasCod = 503 }
        if d.id == "rallypoker" {
            let (ct, dt) = await Red.pedir(base + "api/public/live?v=" + idVisita)
            tiemposCod = ct
            if ct == 200 { tiempos = Red.objeto(dt) }
        }
    }

    var miEvento: Bool {
        let ev = (clas?.str("evento") ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return misEventos.contains { !$0.isEmpty && $0 == ev } || misEventos.count == 1
    }

    /// La fila de la clasificación por cartas de un dorsal.
    func cartasDe(_ dorsal: String) -> [String: Any]? {
        (clas?["clasificacion"] as? [[String: Any]])?.first { PokerModelo.sinCeros($0.str("dorsal")) == dorsal }
    }

    // ---------- inscribirse y pagar (lo mismo que hace la web) ----------
    /// Devuelve: (mensaje para enseñar, url de pago o de la cuenta a abrir)
    func inscribir(_ eventoId: Int) async -> (String?, String?) {
        guard !ocupado else { return (nil, nil) }
        ocupado = true
        let r = await Cuenta.pedir("POST", "/api/inscripciones", cuerpo: ["evento_id": eventoId], token: Cuenta.shared.token)
        ocupado = false
        let j = r.json
        if j.str("status") != "ok" { return error(j.str("codigo")) }
        let i = j["inscripcion"] as? [String: Any]
        if let i = i, i.str("estado") == "pendiente", pagoTarjeta, i.int("importe_cent") > 0 { return await pagar(i.int("id")) }
        await cargar()
        return (i?.str("estado") == "pagada"
                ? t("¡Inscrito! Tu dorsal está en «Mis inscripciones».", "Inscrit! El teu dorsal és a «Les meves inscripcions».", "Registered! Your number is under «My entries».")
                : t("Inscripción hecha. Queda pendiente de pago.", "Inscripció feta. Queda pendent de pagament.", "Entry made. Payment pending."), nil)
    }

    func pagar(_ inscId: Int) async -> (String?, String?) {
        guard !ocupado else { return (nil, nil) }
        ocupado = true
        let r = await Cuenta.pedir("POST", "/api/inscripciones/\(inscId)/pagar", cuerpo: [:], token: Cuenta.shared.token)
        ocupado = false
        let j = r.json, url = j.str("url")
        if j.str("status") == "ok", url.hasPrefix("https://") { return (nil, url) }     // la página de pago de Stripe
        return error(j.str("codigo"))
    }

    private func error(_ codigo: String) -> (String?, String?) {
        let cuenta = Cuenta.base + "/?lang=" + Idioma.codigo
        switch codigo {
        case "perfil_incompleto":
            return (t("Antes de inscribirte, completa tu teléfono y tu moto en «Mis datos».", "Abans d'inscriure't, completa el teu telèfon i la teva moto a «Les meves dades».", "Before registering, add your phone and bike under «My details»."), cuenta)
        case "sin_verificar": return (t("Confirma tu email antes de inscribirte (mira tu correo).", "Confirma el teu correu abans d'inscriure't (mira el teu correu).", "Confirm your email before registering (check your inbox)."), nil)
        case "evento_cerrado": return (t("Las inscripciones de este evento están cerradas.", "Les inscripcions d'aquest esdeveniment estan tancades.", "Registration for this event is closed."), nil)
        case "evento_completo": return (t("No quedan plazas.", "No queden places.", "No places left."), nil)
        case "ya_inscrito": return (t("Ya estás inscrito en este evento.", "Ja estàs inscrit en aquest esdeveniment.", "You are already registered for this event."), nil)
        case "no_sesion":
            Cuenta.shared.salir()
            return (t("Vuelve a entrar con tu cuenta.", "Torna a entrar amb el teu compte.", "Please sign in again."), nil)
        case "": return (t("Sin conexión. Inténtalo con cobertura.", "Sense connexió. Torna-ho a provar amb cobertura.", "No connection. Try again with signal."), nil)
        default: return (t("No se ha podido hacer aquí. Te abro tu cuenta para terminarlo.", "No s'ha pogut fer aquí. T'obro el teu compte per acabar-ho.", "Couldn't do it here. Opening your account to finish."), cuenta + "#eventos")
        }
    }
}

struct PokerView: View {
    let d: PruebaWeb
    @StateObject private var m: PokerModelo
    @EnvironmentObject var central: Central
    @EnvironmentObject var cuenta: Cuenta
    @Environment(\.dismiss) var cerrar
    @State private var web: String? = nil
    @State private var entrar = false
    @State private var ficha: [String: Any]? = nil
    @State private var ajustes = false
    @State private var aviso: String? = nil
    @State private var irGPS = false
    private let refresco = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(d: PruebaWeb) { self.d = d; _m = StateObject(wrappedValue: PokerModelo(d)) }

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    cabecera
                    if m.cargando && m.eventos.isEmpty && !m.sinRed {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    } else if m.sinRed {
                        Texto(t("Sin conexión con onesecond.es. Inténtalo con cobertura.", "Sense connexió amb onesecond.es. Torna-ho a provar amb cobertura.", "No connection to onesecond.es. Try again with signal."), 14, .naranja, .medium).padding(.top, 18)
                        BotonP(t("Reintentar", "Tornar-ho a provar", "Retry"), true) { Task { await m.cargar() } }.padding(.top, 10)
                    } else {
                        cuerpo
                    }
                    BotonP(t("Web de ", "Web de ", "") + d.nombre + (Idioma.actual == 2 ? " website" : "") + "  ↗", false) { web = "https://onesecond.es" + d.web }
                        .padding(.top, 22)
                }
                .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 28)
            }
            if let a = aviso {
                VStack { Spacer(); Text(a).font(.callout.weight(.semibold)).foregroundColor(.white).multilineTextAlignment(.center)
                    .padding(14).frame(maxWidth: .infinity).background(Color.panel.opacity(0.97)).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borde)).padding(16) }
                    .transition(.move(edge: .bottom))
            }
            NavigationLink(isActive: $irGPS) { PruebaView(p: .rally) } label: { EmptyView() }.hidden()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await m.cargar() }
        .onReceive(refresco) { _ in Task { await m.cargarClas() } }
        .onChange(of: cuenta.token) { _ in Task { await m.cargar() } }
        .sheet(isPresented: Binding(get: { web != nil }, set: { if !$0 { web = nil; Task { await m.cargar() } } })) {
            WebCuentaView(url: web ?? "").environmentObject(cuenta).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $entrar) { EntrarView().environmentObject(cuenta).preferredColorScheme(.dark) }
        .sheet(isPresented: Binding(get: { ficha != nil }, set: { if !$0 { ficha = nil } })) {
            FichaPoker(m: m, x: ficha ?? [:]).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $ajustes) { AjustesPoker(d: d).preferredColorScheme(.dark) }
    }

    private func mostrar(_ s: String?) {
        guard let s = s else { return }
        withAnimation { aviso = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { withAnimation { if aviso == s { aviso = nil } } }
    }
    private func resultado(_ r: (String?, String?)) { mostrar(r.0); if let u = r.1 { web = u } }

    // ---------- piezas ----------
    private var cabecera: some View {
        HStack(spacing: 14) {
            Image(d.icono).resizable().scaledToFit().frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.nombre).font(.custom("TeXGyrePagella-Bold", size: 21)).foregroundColor(.white).shadow(color: .black.opacity(0.67), radius: 4, y: 1)
                Text(d.subtitulo).font(.system(size: 12.5)).foregroundColor(.white.opacity(215 / 255)).shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(LinearGradient(colors: d.metal.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var cuerpo: some View {
        Etiqueta(t("PRÓXIMOS EVENTOS", "PROPERS ESDEVENIMENTS", "UPCOMING EVENTS")).padding(.top, 20)
        if m.eventos.isEmpty {
            Caja { Texto(t("De momento no hay eventos anunciados. Vuelve pronto.", "De moment no hi ha esdeveniments anunciats. Torna aviat.", "No events announced yet. Check back soon."), 14, .suave) }.padding(.top, 8)
        } else {
            ForEach(Array(m.eventos.enumerated()), id: \.offset) { _, e in tarjetaEvento(e).padding(.top, 8) }
        }

        Etiqueta(t("MIS INSCRIPCIONES Y RESULTADOS", "LES MEVES INSCRIPCIONS I RESULTATS", "MY ENTRIES AND RESULTS")).padding(.top, 22)
        if !m.conectado {
            Caja {
                Texto(t("Entra con tu cuenta One Second para inscribirte, pagar y ver tus resultados.", "Entra amb el teu compte One Second per inscriure't, pagar i veure els teus resultats.", "Sign in with your One Second account to register, pay and see your results."), 14, .texto)
                BotonP(t("Entrar con mi cuenta", "Entrar amb el meu compte", "Sign in"), true) { entrar = true }.padding(.top, 12)
                BotonP(t("Crear cuenta nueva", "Crear un compte nou", "Create a new account"), false, color: .oroCuenta) { web = Cuenta.base + "/registro?lang=" + Idioma.codigo }.padding(.top, 8)
            }.padding(.top, 8)
        } else if m.mias.isEmpty {
            Caja { Texto(t("Todavía no te has inscrito en ninguna " + d.nombre + ".", "Encara no t'has inscrit a cap " + d.nombre + ".", "You haven't entered any " + d.nombre + " yet."), 14, .suave) }.padding(.top, 8)
        } else {
            ForEach(Array(m.mias.enumerated()), id: \.offset) { _, i in tarjetaInsc(i).padding(.top, 8) }
        }

        if d.id == "rallypoker" {
            Etiqueta(t("EL DÍA DE LA PRUEBA", "EL DIA DE LA PROVA", "ON THE DAY")).padding(.top, 22)
            Caja {
                Texto(t("Rally Poker se cronometra con One Second Rally: vincula y pulsa EMITIR allí.", "Rally Poker es cronometra amb One Second Rally: vincula i prem EMETRE allà.", "Rally Poker is timed with One Second Rally: link and tap START there."), 14, .texto)
                BotonP("⏱  " + t("Abrir el GPS (One Second Rally)", "Obrir el GPS (One Second Rally)", "Open GPS (One Second Rally)"), true) { irGPS = true }.padding(.top, 12)
            }.padding(.top, 8)
            Etiqueta(t("CLASIFICACIÓN POR TIEMPOS · LOS 25 PRIMEROS", "CLASSIFICACIÓ PER TEMPS · ELS 25 PRIMERS", "STANDINGS BY TIME · TOP 25")).padding(.top, 22)
            Caja { tiemposVista }.padding(.top, 8)
        }
        Etiqueta(d.id == "rallypoker" ? t("CLASIFICACIÓN POR CARTAS · LOS 25 PRIMEROS", "CLASSIFICACIÓ PER CARTES · ELS 25 PRIMERS", "STANDINGS BY CARDS · TOP 25")
                 : t("CLASIFICACIÓN · LOS 25 PRIMEROS", "CLASSIFICACIÓ · ELS 25 PRIMERS", "STANDINGS · TOP 25")).padding(.top, 22)
        Caja { clasVista }.padding(.top, 8)
        BotonP("⚙  " + t("Ajustes", "Ajustos", "Settings"), false) { ajustes = true }.padding(.top, 26)
    }

    private func tarjetaEvento(_ e: [String: Any]) -> some View {
        let precio = e.int("precio_cent"), plazas = e.int("plazas"), ocup = e.int("ocupadas")
        var info = precio > 0 ? Poker.euros(precio) : t("Gratis", "Gratuït", "Free")
        if plazas > 0 { info += " · " + t("Plazas libres: ", "Places lliures: ", "Places left: ") + String(max(0, plazas - ocup)) }
        let lin = [Poker.fecha(e.str("fecha")), e.str("hora"), Cuenta.lugar(e)].filter { !$0.isEmpty }.joined(separator: " · ")
        let ya = m.mias.last { $0.int("evento_id") == e.int("id") && ($0.str("tipo").isEmpty ? "piloto" : $0.str("tipo")) == "piloto" }
        let afi = e["afi"] as? [String: Any]
        return Caja {
            Text(Cuenta.nombre(e)).font(.custom("TeXGyrePagella-Bold", size: 18)).foregroundColor(.texto)
            if !lin.isEmpty { Texto(lin, 13, .oroCuenta, .medium).padding(.top, 3) }
            Texto(info, 13, .suave).padding(.top, 3)
            Group {
                if let y = ya, y.str("estado") == "pagada" {
                    BotonP("✓  " + t("Inscrito", "Inscrit", "Registered") + (y.str("dorsal_txt").isEmpty ? "" : " · " + t("dorsal ", "dorsal ", "no. ") + y.str("dorsal_txt")), false, color: Color(hex: 0x3FBF7F)) {
                        web = Cuenta.base + "/?lang=" + Idioma.codigo }
                } else if let y = ya {
                    let paga = m.pagoTarjeta && y.int("importe_cent") > 0
                    BotonP(paga ? t("Pagar la inscripción", "Pagar la inscripció", "Pay the entry fee") : t("Inscripción pendiente", "Inscripció pendent", "Entry pending"), true) {
                        if paga { Task { resultado(await m.pagar(y.int("id"))) } } else { web = Cuenta.base + "/?lang=" + Idioma.codigo }
                    }
                } else if e["abierto"] != nil && !e.bool("abierto") {
                    BotonP(t("Inscripciones cerradas", "Inscripcions tancades", "Registration closed"), false) {}.disabled(true).opacity(0.55)
                } else if e.bool("completo") {
                    BotonP(t("Completo", "Complet", "Full"), false) {}.disabled(true).opacity(0.55)
                } else {
                    BotonP(t("Inscribirme", "Inscriure'm", "Register"), true) {
                        if !cuenta.conectado { entrar = true; return }
                        mostrar(t("Un momento…", "Un moment…", "One moment…"))
                        Task { resultado(await m.inscribir(e.int("id"))) }
                    }
                }
            }.padding(.top, 12)
            if let a = afi, a.bool("activo"), e["abierto"] == nil || e.bool("abierto") {
                BotonP("🏠  " + t("Jugar desde casa", "Jugar des de casa", "Play from home"), false) {
                    web = Cuenta.base + "/?lang=" + Idioma.codigo + "#afi=\(e.int("id"))" }.padding(.top, 8)
            }
        }
    }

    private func tarjetaInsc(_ i: [String: Any]) -> some View {
        let e = i["evento"] as? [String: Any] ?? [:]
        let afi = i.str("tipo") == "aficionado"
        let est = i.str("estado")
        var l2 = Poker.fecha(e.str("fecha"))
        if !i.str("dorsal_txt").isEmpty { l2 += (l2.isEmpty ? "" : " · ") + (afi ? t("código ", "codi ", "code ") : t("dorsal ", "dorsal ", "no. ")) + i.str("dorsal_txt") }
        return Caja {
            Text(Cuenta.nombre(e) + (afi ? " · " + t("desde casa", "des de casa", "from home") : "")).font(.custom("TeXGyrePagella-Bold", size: 17)).foregroundColor(.texto)
            Texto(l2, 13, .suave).padding(.top, 3)
            if let dip = i["diploma"] as? [String: Any] {
                Texto("🏁  " + resumen(dip), 15.5, .oroCuenta, .medium).padding(.top, 10)
                BotonP(t("Ver el diploma y la clasificación", "Veure el diploma i la classificació", "See certificate and results"), true) { web = Cuenta.base + "/?lang=" + Idioma.codigo }.padding(.top, 10)
            } else if est == "pagada" {
                Texto(t("✓ Confirmada. El resultado saldrá aquí cuando la organización lo publique.", "✓ Confirmada. El resultat sortirà aquí quan l'organització el publiqui.", "✓ Confirmed. Your result will appear here once the organisers publish it."), 13.5, Color(hex: 0x3FBF7F)).padding(.top, 8)
            } else if est == "pendiente" {
                Texto(t("Pendiente de pago.", "Pendent de pagament.", "Payment pending."), 13.5, .naranja).padding(.top, 8)
                if m.pagoTarjeta && i.int("importe_cent") > 0 {
                    BotonP(t("Pagar", "Pagar", "Pay") + " · " + Poker.euros(i.int("importe_cent")), true) { Task { resultado(await m.pagar(i.int("id"))) } }.padding(.top, 10)
                }
            } else if !est.isEmpty { Texto(est, 13, .suave).padding(.top, 6) }
        }
    }

    /// Lo mismo que «Mis inscripciones» de la web: posición y, según la prueba, la mano o los puntos.
    private func resumen(_ x: [String: Any]) -> String {
        var p: [String] = []
        if x.int("pos") > 0 {
            let de = x.str("de")
            p.append(Idioma.actual == 0 ? "\(x.int("pos"))º de \(de)" : Idioma.actual == 1 ? "\(x.int("pos")) de \(de)" : "\(x.int("pos")) of \(de)")
        }
        let app = x.str("app").isEmpty ? d.id : x.str("app")
        if app == "rallypoker" && x.str("tipo") != "aficionado" && !x.str("pen").isEmpty && x.str("pen") != "0" { p.append(t("Penalización ", "Penalització ", "Penalty ") + x.str("pen")) }
        if app == "holdemrun", let pu = x["puntos"], !(pu is NSNull) { p.append(x.str("puntos") + t(" puntos", " punts", " points")) }
        if (app == "pokerrun" || app == "rallypoker") && !x.str("mano").isEmpty { p.append(x.str("mano")) }
        return p.isEmpty ? t("Resultado publicado", "Resultat publicat", "Result published") : p.joined(separator: " · ")
    }

    private var cargandoClas: some View { Texto(t("Cargando la clasificación…", "Carregant la classificació…", "Loading standings…"), 14, .suave) }
    private var noSeCarga: String {
        t("No se ha podido cargar la clasificación. Se vuelve a intentar en 30 segundos.", "No s'ha pogut carregar la classificació. Es torna a provar d'aquí a 30 segons.", "The standings could not be loaded. Trying again in 30 seconds.")
    }
    private var mucha: String {
        t("Ahora mismo hay mucha gente mirando la clasificación. Se vuelve a intentar en 30 segundos.", "Ara mateix hi ha molta gent mirant la classificació. Es torna a provar d'aquí a 30 segons.", "Lots of people are viewing the standings right now. Trying again in 30 seconds.")
    }

    @ViewBuilder private var clasVista: some View {
        if let j = m.clas, let cl = j["clasificacion"] as? [[String: Any]] {
            let fin = j.bool("final")
            HStack {
                Text(j.str("evento").isEmpty ? d.nombre : j.str("evento")).font(.custom("TeXGyrePagella-Bold", size: 16)).foregroundColor(.texto)
                Spacer()
                Texto(fin ? t("RESULTADOS FINALES", "RESULTATS FINALS", "FINAL RESULTS") : "● " + t("EN DIRECTO", "EN DIRECTE", "LIVE"), 11, fin ? .oroCuenta : Color(hex: 0x3FBF7F), .medium)
            }
            Texto("\(cl.count) " + t("participantes", "participants", "participants"), 13, .suave).padding(.top, 2)
            if cl.isEmpty {
                Texto(t("La clasificación saldrá aquí cuando empiece el evento.", "La classificació sortirà aquí quan comenci l'esdeveniment.", "The standings will appear here once the event starts."), 14, .suave).padding(.top, 12)
            }
            ForEach(Array(cl.prefix(25).enumerated()), id: \.offset) { k, x in
                filaClas(x, yo: m.miEvento && m.misDorsales.contains(x.str("dorsal")))
                    .contentShape(Rectangle()).onTapGesture { ficha = x }.padding(.top, k == 0 ? 10 : 2)
            }
            botonCompleta.padding(.top, 14)
            Texto(t("Se abre onesecond.es", "S'obre onesecond.es", "Opens onesecond.es") + d.web.replacingOccurrences(of: "/$", with: "", options: .regularExpression), 12, .suave)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 6)
        } else if m.clasCod == 0 {
            cargandoClas
        } else {
            Texto(m.clasCod == 503 ? mucha : noSeCarga, 14, m.clasCod == 503 ? .naranja : .suave)
            botonCompleta.padding(.top, 12)
        }
    }

    private var botonCompleta: some View {
        BotonP(t("Ver la clasificación completa", "Veure la classificació completa", "See the full standings") + "  ↗", true) { web = "https://onesecond.es" + d.web }
    }

    private func filaClas(_ x: [String: Any], yo: Bool) -> some View {
        let pos = x.int("posicion")
        let sub: String
        let holdem = d.id == "holdemrun"
        if holdem {
            var mejor = -1
            for h in x["manos"] as? [Any] ?? [] { if let a = h as? [Any], a.count > 3 { mejor = max(mejor, Poker.num(a[3]) ?? -1) } }
            let rec = x.int("recogidas")
            sub = "\(rec) " + (rec == 1 ? t("mano", "mà", "hand") : t("manos", "mans", "hands")) + (mejor >= 0 ? " · " + t("mejor: ", "millor: ", "best: ") + Poker.categoria(mejor) : "")
        } else {
            sub = Poker.nombreMano(x["ev"] as? [Any]) ?? x.str("mano")
        }
        var cs = x["usadas"] as? [Any] ?? []
        if cs.isEmpty { cs = x["cartas"] as? [Any] ?? [] }
        return HStack(spacing: 0) {
            Texto(pos > 0 ? "\(pos)" : "–", 14, pos > 0 && pos <= 3 ? .oroCuenta : Color(hex: 0xC3CDDB), .medium).frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Texto(x.str("nombre") + "  #" + x.str("dorsal"), 13.5, .texto, .medium).lineLimit(1)
                Texto(sub, 12, Color(hex: 0x9FB0C6))
            }.padding(.leading, 10).padding(.trailing, 8)
            Spacer(minLength: 0)
            if holdem {
                VStack(alignment: .trailing, spacing: 0) {
                    Texto(Poker.miles(x.int("total")), 15, .white, .medium)
                    Texto(t("puntos", "punts", "points"), 11, .suave)
                }
            } else {
                HStack(spacing: 2) { ForEach(Array(cs.prefix(5).enumerated()), id: \.offset) { _, c in MiniCarta(c: "\(c)") } }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(yo ? Color.azul.opacity(36 / 255) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(yo ? Color.azul.opacity(140 / 255) : .clear, lineWidth: 1))
    }

    /// Rally Poker: los 25 primeros por tiempos (la web del Rally de Rally Poker).
    @ViewBuilder private var tiemposVista: some View {
        if let j = m.tiempos {
            let fin = j.bool("final")
            let top = j["top"] as? [[String: Any]] ?? []
            HStack {
                Text((j["event"] as? [String: Any])?.str("name") ?? d.nombre).font(.custom("TeXGyrePagella-Bold", size: 16)).foregroundColor(.texto).lineLimit(1)
                Spacer()
                Texto(fin ? t("RESULTADOS FINALES", "RESULTATS FINALS", "FINAL RESULTS") : "● " + t("EN DIRECTO", "EN DIRECTE", "LIVE"), 11.5, fin ? .oroCuenta : Color(hex: 0x3FBF7F), .medium)
            }
            if top.isEmpty {
                Texto(t("La clasificación saldrá aquí cuando empiece el evento.", "La classificació sortirà aquí quan comenci l'esdeveniment.", "The standings will appear here when the event starts."), 14, .suave).padding(.top, 8)
            } else {
                ForEach(Array(top.prefix(25).enumerated()), id: \.offset) { k, x in
                    let dor = PokerModelo.sinCeros(x.str("dorsal"))
                    let cartas = m.cartasDe(dor)
                    let mano = cartas.map { Poker.nombreMano($0["ev"] as? [Any]) ?? $0.str("mano") } ?? ""
                    let yo = m.misDorsales.contains(dor) && (m.misEventos.count == 1 || m.clas != nil)
                    let pos = x.int("pos")
                    HStack(spacing: 0) {
                        Texto(pos > 0 ? "\(pos)" : "–", 14, pos > 0 && pos <= 3 ? .oroCuenta : Color(hex: 0xC3CDDB), .medium).frame(width: 24, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 1) {
                            Texto(x.str("nombre") + "  #" + dor, 13.5, .texto, .medium).lineLimit(1)
                            Texto(x.str("ultimo") + (mano.isEmpty ? "" : " · " + mano), 12, Color(hex: 0x9FB0C6)).lineLimit(1)
                        }.padding(.leading, 10).padding(.trailing, 8)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 0) {
                            Texto(x.str("pen"), 15, .white, .medium)
                            Texto(x.str("dif"), 11, pos == 1 ? .oroCuenta : .suave)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(yo ? Color.azul.opacity(36 / 255) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(yo ? Color.azul.opacity(140 / 255) : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { ficha = cartas ?? ["nombre": x.str("nombre"), "dorsal": dor, "motoclub": x.str("motoclub"), "moto": x.str("moto")] }
                    .padding(.top, k == 0 ? 10 : 2)
                }
                botonCompleta.padding(.top, 14)
            }
        } else if m.tiemposCod == 0 {
            cargandoClas
        } else {
            Texto(m.tiemposCod == 503 ? mucha : noSeCarga, 14, .suave)
        }
    }
}

/// La ficha de un participante (como la ventana de la web).
struct FichaPoker: View {
    @ObservedObject var m: PokerModelo
    let x: [String: Any]
    @Environment(\.dismiss) var cerrar
    @State private var det: [String: Any]? = nil
    @State private var detError = false

    var body: some View {
        let est = m.clas ?? [:]
        let total = (est["clasificacion"] as? [Any])?.count ?? 0
        let nPuntos = est["num_puntos"] == nil ? 5 : est.int("num_puntos", 5)
        let fin = est.bool("final")
        ZStack {
            Color.fondo.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(x.str("nombre")).font(.custom("TeXGyrePagella-Bold", size: 21)).foregroundColor(.texto)
                    Texto(t("Dorsal ", "Dorsal ", "No. ") + x.str("dorsal") + (x.str("motoclub").isEmpty ? "" : " · " + x.str("motoclub")) + (x.str("moto").isEmpty ? "" : " · " + x.str("moto")), 12.5, .suave).padding(.top, 3)
                    if m.d.id == "rallypoker" {
                        Group {
                            if let dd = det { TiemposVista(det: dd) }
                            else if detError { Texto(t("No se han podido cargar sus tiempos.", "No s'han pogut carregar els seus temps.", "Couldn't load the times."), 13.5, .naranja) }
                            else { Texto(t("Cargando sus tiempos…", "Carregant els seus temps…", "Loading times…"), 14, .suave) }
                        }.padding(.top, 14)
                        Text(t("SUS CARTAS", "LES SEVES CARTES", "CARDS")).font(.system(size: 11, weight: .medium)).tracking(1.6).foregroundColor(.suave).padding(.top, 18)
                    }
                    if m.d.id == "holdemrun" { holdem(est: est, nPuntos: nPuntos, total: total) }
                    else { poker(nPuntos: nPuntos, total: total, fin: fin) }
                    HStack(spacing: 8) {
                        if #available(iOS 16.0, *) {
                            ShareLink(item: compartir(est: est, nPuntos: nPuntos, total: total, fin: fin)) {
                                Text(t("Compartir", "Compartir", "Share")).font(.system(size: 14.5, weight: .medium)).foregroundColor(Color(hex: 0x3FBF7F))
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x2B6B4A), lineWidth: 1))
                            }
                        } else {
                            BotonP(t("Compartir", "Compartir", "Share"), false, color: Color(hex: 0x3FBF7F)) {
                                Compartir.texto(compartir(est: est, nPuntos: nPuntos, total: total, fin: fin))
                            }
                        }
                        BotonP(t("Cerrar", "Tancar", "Close"), false) { cerrar() }
                    }.padding(.top, 14)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.panel))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0x2B3648), lineWidth: 1))
                .padding(14)
            }
        }
        .task {
            guard m.d.id == "rallypoker" else { return }
            let dor = x.str("dorsal").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            let (c, d) = await Red.pedir("https://onesecond.es" + m.d.web + "api/public/live/participante?d=" + dor)
            if c == 200 { det = Red.objeto(d) } else { detError = true }
        }
    }

    private func nombrePunto(_ n: Int) -> String {
        for p in m.clas?["puntos"] as? [[String: Any]] ?? [] where p.int("numero") == n && !p.str("nombre").isEmpty { return p.str("nombre") }
        return t("Punto ", "Punt ", "Checkpoint ") + "\(n)"
    }
    private func puesto(_ p: Int, _ de: Int) -> String { t("Puesto \(p) de \(de)", "Lloc \(p) de \(de)", "Position \(p) of \(de)") }

    @ViewBuilder private func holdem(est: [String: Any], nPuntos: Int, total: Int) -> some View {
        let manos = x["manos"] as? [Any] ?? []
        let tabs = est["tableros"] as? [String: Any] ?? [:]
        let puntua = manos.contains { ($0 as? [Any])?.count ?? 0 > 3 }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<nPuntos, id: \.self) { mi in
                let h = mi < manos.count ? manos[mi] as? [Any] : nil
                let tab = tabs["\(mi + 1)"] as? [Any]
                let usadas = (h?.count ?? 0) > 5 ? (h?[5] as? [Any])?.map { "\($0)" } : nil
                VStack(alignment: .leading, spacing: 5) {
                    Texto("\(mi + 1) · " + nombrePunto(mi + 1), 12.5, .suave)
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { k in
                            let cc = h != nil && k < h!.count ? h![k] as? String : nil
                            Carta(c: cc, ancho: 22, alto: 30, letra: 10.5, gris: usadas != nil && !(usadas!.contains(cc ?? "")))
                        }
                        Texto("+", 13, Color(hex: 0x5B677A), .medium).padding(.horizontal, 2)
                        ForEach(0..<5, id: \.self) { k in
                            let cc = tab != nil && k < tab!.count ? tab![k] as? String : nil
                            Carta(c: cc, ancho: 22, alto: 30, letra: 10.5, gris: usadas != nil && cc != nil && !usadas!.contains(cc!))
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 0) {
                            if h == nil {
                                Texto("0", 15, .white, .medium)
                                Texto(t("No recogida", "No recollida", "Not collected"), 11.5, .suave)
                            } else if h!.count > 3 {
                                Texto("\(Poker.num(h![2]) ?? 0)", 15, .white, .medium)
                                let cat = Poker.num(h![3]) ?? -1
                                Texto(Poker.nombreMano([cat, h!.count > 4 ? (h![4] as? [Any] ?? []) : []]) ?? Poker.categoria(cat), 11.5, Color(hex: 0x9FB0C6)).multilineTextAlignment(.trailing)
                            } else {
                                Texto(t("Se destapa en la meta", "Es destapa a la meta", "Revealed at the finish"), 11.5, Color(hex: 0xD6B65A)).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }.padding(.vertical, 8)
                Raya()
            }
            HStack {
                Texto(t("Total", "Total", "Total"), 13, .suave)
                Spacer()
                Text(puntua ? "\(x.int("total")) " + t("puntos", "punts", "points") : "\(x.int("recogidas")) " + t("de ", "de ", "of ") + "\(nPuntos) " + t("manos", "mans", "hands"))
                    .font(.custom("TeXGyrePagella-Bold", size: 20)).foregroundColor(Color(hex: 0xF6E7B0))
            }.padding(.top, 10)
            Texto(puntua && x.int("posicion") > 0 ? puesto(x.int("posicion"), total) : t("Se puntúa al destapar el tablero", "Es puntua en destapar el tauler", "Scored when the board is revealed"), 14, .texto, .medium)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 4)
        }.padding(.top, 8)
    }

    @ViewBuilder private func poker(nPuntos: Int, total: Int, fin: Bool) -> some View {
        let cs = (x["cartas"] as? [Any] ?? []).map { "\($0)" }
        let usadas = (x["usadas"] as? [Any] ?? []).map { "\($0)" }
        let n = cs.count
        let huecos = max(n, min(nPuntos, 5))
        let an = huecos > 5 ? max(30, 270 / huecos) : 50
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<huecos, id: \.self) { k in
                    let cc = k < n ? cs[k] : nil
                    Carta(c: cc, ancho: CGFloat(an), alto: CGFloat(an) * 1.42, letra: an > 40 ? 18 : 12, gris: n > 5 && !usadas.contains(cc ?? ""))
                }
            }.frame(maxWidth: .infinity).padding(.top, 14)
            Text(Poker.nombreMano(x["ev"] as? [Any]) ?? x.str("mano")).font(.custom("TeXGyrePagella-Bold", size: 19)).foregroundColor(Color(hex: 0xF0D68C))
                .multilineTextAlignment(.center).padding(.top, 12)
            Texto(posTexto(n: n, nPuntos: nPuntos, total: total, fin: fin), 14, .texto, .medium).multilineTextAlignment(.center).padding(.top, 4)
            let porPunto = x["cartas_por_punto"] as? [Any] ?? []
            if !porPunto.isEmpty {
                Raya().padding(.top, 12)
                ForEach(0..<porPunto.count, id: \.self) { k in
                    let cc = porPunto[k] as? String
                    HStack {
                        Texto(nombrePunto(k + 1), 13.5, Color(hex: 0xC9D3DF))
                        Spacer()
                        if let c = cc, !c.isEmpty {
                            let rojo = c.hasSuffix("♥") || c.hasSuffix("♦")
                            Text(c).font(.system(size: 15, weight: .medium)).foregroundColor(rojo ? Color(hex: 0xC8232C) : Color(hex: 0x1B1F26))
                                .padding(.horizontal, 7).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xF2F2EE)))
                        } else { Texto("—", 15, .suave, .medium) }
                    }.padding(.horizontal, 2).padding(.vertical, 7)
                    Raya()
                }
            }
        }
    }

    private func posTexto(n: Int, nPuntos: Int, total: Int, fin: Bool) -> String {
        let falta = max(0, nPuntos - n)
        var pos = x.bool("completa") || fin || falta == 0 ? puesto(x.int("posicion"), total)
            : n == 0 ? t("Aún sin cartas", "Encara sense cartes", "No cards yet")
            : falta == 1 ? t("Le falta 1 carta", "Li falta 1 carta", "1 card to go")
            : t("Le faltan \(falta) cartas", "Li falten \(falta) cartes", "\(falta) cards to go")
        if x.bool("empate") && (x.bool("completa") || fin) { pos += " " + t("(empate)", "(empat)", "(tie)") }
        return pos
    }

    private func compartir(est: [String: Any], nPuntos: Int, total: Int, fin: Bool) -> String {
        let ev = est.str("evento").isEmpty ? m.d.nombre : est.str("evento")
        let quien = x.str("nombre") + " (" + t("dorsal ", "dorsal ", "no. ") + x.str("dorsal") + ") · "
        let txt: String
        if m.d.id == "holdemrun" {
            let manos = x["manos"] as? [Any] ?? []
            let puntua = manos.contains { ($0 as? [Any])?.count ?? 0 > 3 }
            let tot = puntua ? "\(x.int("total")) " + t("puntos", "punts", "points") : "\(x.int("recogidas")) " + t("de ", "de ", "of ") + "\(nPuntos) " + t("manos", "mans", "hands")
            let pos = puntua && x.int("posicion") > 0 ? puesto(x.int("posicion"), total) : t("Se puntúa al destapar el tablero", "Es puntua en destapar el tauler", "Scored when the board is revealed")
            txt = quien + tot + " · " + pos
        } else {
            let n = (x["cartas"] as? [Any] ?? []).count
            txt = quien + (Poker.nombreMano(x["ev"] as? [Any]) ?? x.str("mano")) + " · " + posTexto(n: n, nPuntos: nPuntos, total: total, fin: fin)
        }
        return txt + " · " + ev + "\nhttps://onesecond.es" + m.d.web + "#d=" + x.str("dorsal")
    }
}

/// El desglose de tiempos de un piloto en cada control (Rally Poker y One Second Rally).
struct TiemposVista: View {
    let det: [String: Any]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                bloque(det.int("pos") > 0 ? "\(det.int("pos"))º" : "–", t("Puesto", "Lloc", "Position"), .oroCuenta)
                bloque(det.str("pen").isEmpty ? "–" : det.str("pen"), t("Penalización", "Penalització", "Penalty"), .white)
                bloque(det.str("total").isEmpty ? "–" : det.str("total"), t("Tiempo total", "Temps total", "Total time"), .texto)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x18202C)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borde, lineWidth: 1))
            let est = det.str("estado"), pm = det.str("pen_man")
            if !est.isEmpty || !pm.isEmpty {
                Texto(est + (pm.isEmpty ? "" : " · " + t("penalización manual ", "penalització manual ", "manual penalty ") + pm), 12, .suave)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 6)
            }
            Text(t("TIEMPOS EN CADA CONTROL", "TEMPS A CADA CONTROL", "TIMES AT EACH CHECKPOINT")).font(.system(size: 11, weight: .medium)).tracking(1.6).foregroundColor(.suave).padding(.top, 12)
            let cs = (det["controles"] as? [[String: Any]] ?? []).filter { !$0.bool("oculto") }
            if cs.isEmpty {
                Texto(t("Aún no ha pasado por ningún control.", "Encara no ha passat per cap control.", "No checkpoints passed yet."), 13, .suave).padding(.top, 6)
            }
            ForEach(Array(cs.enumerated()), id: \.offset) { _, x in
                Raya().padding(.top, 6)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Texto("\(x.int("orden")). " + x.str("control"), 14, .texto, .medium)
                        Texto(sub(x), 12, .suave)
                    }
                    Spacer()
                    let tipo = x.str("tipo"), salida = tipo == "salida"
                    let col: Color = tipo == "exacto" ? Color(hex: 0x62D696) : tipo == "retraso" ? Color(hex: 0xF07878) : tipo == "adelanto" ? Color(hex: 0x7FB2F0) : .suave
                    VStack(alignment: .trailing, spacing: 1) {
                        Texto(salida ? t("Salida", "Sortida", "Start") : (x.str("desvio").isEmpty ? "—" : x.str("desvio")), 14, col, .medium)
                        if !salida && !x.str("pen").isEmpty { Texto("pen. " + x.str("pen"), 11.5, .suave) }
                    }
                }.padding(.top, 6)
            }
        }
    }
    private func sub(_ x: [String: Any]) -> String {
        var s = x.str("hora")
        if !x.str("tramo").isEmpty { s += "  ·  " + t("tramo ", "tram ", "stage ") + x.str("tramo") + (x.str("obj").isEmpty ? "" : " / " + x.str("obj")) }
        if !x.str("neutral").isEmpty { s += "  ·  " + x.str("neutral") }
        return s
    }
    private func bloque(_ v: String, _ e: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text(v).font(.custom("TeXGyrePagella-Bold", size: 18)).foregroundColor(c)
            Texto(e, 11, .suave)
        }.frame(maxWidth: .infinity)
    }
}

/// Ajustes de las pruebas de póker: aquí no se emite la posición, así que solo «Acerca de» y la versión.
struct AjustesPoker: View {
    let d: PruebaWeb
    @Environment(\.dismiss) var cerrar
    var body: some View {
        ZStack {
            Color.panel.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Text(t("Ajustes", "Ajustos", "Settings")).font(.custom("TeXGyrePagella-Bold", size: 24)).foregroundColor(.texto)
                    Image(d.icono).resizable().scaledToFit().frame(width: 84, height: 84).padding(.top, 16)
                    Text(d.nombre).font(.custom("TeXGyrePagella-Bold", size: 20)).foregroundColor(.texto).padding(.top, 8)
                    Texto(t("App One Second · versión ", "App One Second · versió ", "One Second app · version ") + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""), 13.5, .suave).padding(.top, 2)
                    Texto(t("Idea original y programa: Jaume Garcia", "Idea original i programa: Jaume Garcia", "Original idea and software: Jaume Garcia"), 14, .texto).padding(.top, 16)
                    Link(t("Contacto", "Contacte", "Contact") + ": info@onesecond.es", destination: URL(string: "mailto:info@onesecond.es")!)
                        .font(.system(size: 14)).foregroundColor(Color(hex: 0x7FB2F0)).padding(.top, 14)
                    Link("onesecond.es" + d.web.replacingOccurrences(of: "/$", with: "", options: .regularExpression), destination: URL(string: "https://onesecond.es" + d.web)!)
                        .font(.system(size: 14)).foregroundColor(Color(hex: 0x7FB2F0)).padding(.top, 8)
                    Texto("© 2026 One Second · Jaume Garcia", 12, .suave).padding(.top, 12)
                    BotonP(t("Cerrar", "Tancar", "Close"), true) { cerrar() }.padding(.top, 20)
                }.padding(24).multilineTextAlignment(.center)
            }
        }
    }
}

// ---------- piezas comunes ----------
struct Texto: View {
    let s: String; let tam: CGFloat; let color: Color; let peso: Font.Weight
    init(_ s: String, _ tam: CGFloat, _ color: Color, _ peso: Font.Weight = .regular) { self.s = s; self.tam = tam; self.color = color; self.peso = peso }
    var body: some View { Text(s).font(.system(size: tam, weight: peso)).foregroundColor(color).lineSpacing(tam * 0.12).fixedSize(horizontal: false, vertical: true) }
}

struct Etiqueta: View {
    let s: String
    init(_ s: String) { self.s = s }
    var body: some View { Text(s).font(.system(size: 10.5, weight: .medium)).tracking(1.7).foregroundColor(.suave) }
}

struct Caja<C: View>: View {
    let c: C
    init(@ViewBuilder _ c: () -> C) { self.c = c() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { c }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borde, lineWidth: 1))
    }
}

struct BotonP: View {
    let s: String; let principal: Bool; var color: Color? = nil; let accion: () -> Void
    init(_ s: String, _ principal: Bool, color: Color? = nil, accion: @escaping () -> Void) { self.s = s; self.principal = principal; self.color = color; self.accion = accion }
    var body: some View {
        Button(action: accion) {
            Text(s).font(.system(size: 14.5, weight: .medium)).multilineTextAlignment(.center)
                .foregroundColor(principal ? .white : (color ?? Color(hex: 0xC9D3DF)))
                .frame(maxWidth: .infinity).padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(principal ? Color.azul : .clear))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(principal ? .clear : (color ?? .borde), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct Raya: View { var body: some View { Rectangle().fill(Color(hex: 0x1D2531)).frame(height: 1) } }

/// Una carta: grande (ficha) o pequeña (tablero). gris = no entra en la jugada; nil = hueco.
struct Carta: View {
    let c: String?; let ancho: CGFloat; let alto: CGFloat; let letra: CGFloat; let gris: Bool
    var body: some View {
        if let c = c, c.count >= 2 {
            let palo = String(c.suffix(1)), rojo = palo == "♥" || palo == "♦"
            Text(String(c.dropLast()) + "\n" + palo).font(.system(size: letra, weight: .medium)).multilineTextAlignment(.center).lineSpacing(-2)
                .foregroundColor(rojo ? Color(hex: 0xC8232C) : Color(hex: 0x1B1F26))
                .frame(width: ancho, height: alto).background(RoundedRectangle(cornerRadius: ancho > 30 ? 7 : 4).fill(Color(hex: 0xF7F7F4)))
                .opacity(gris ? 0.38 : 1)
        } else {
            RoundedRectangle(cornerRadius: ancho > 30 ? 7 : 4).stroke(Color(hex: 0x3A4556), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: ancho, height: alto)
        }
    }
}

struct MiniCarta: View {
    let c: String
    var body: some View {
        if c.count >= 2 {
            let palo = String(c.suffix(1)), rojo = palo == "♥" || palo == "♦"
            Text(String(c.dropLast()) + "\n" + palo).font(.system(size: 10, weight: .medium)).multilineTextAlignment(.center).lineSpacing(-2)
                .foregroundColor(rojo ? Color(hex: 0xC8232C) : Color(hex: 0x1B1F26))
                .frame(width: 19, height: 26).background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xF2F2EE)))
        }
    }
}

enum Compartir {
    static func texto(_ s: String) {
        let av = UIActivityViewController(activityItems: [s], applicationActivities: nil)
        let raiz = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        var top = raiz
        while let p = top?.presentedViewController { top = p }
        top?.present(av, animated: true)
    }
}

/// Nombres de las jugadas de póker, igual que la web (ev = [categoría, [valores]]).
enum Poker {
    static func num(_ v: Any?) -> Int? { (v as? Int) ?? (v as? NSNumber)?.intValue ?? (v as? String).flatMap(Int.init) }

    static let catEs = ["Carta alta", "Pareja", "Doble pareja", "Trío", "Escalera", "Color", "Full", "Póker", "Escalera de color"]
    static let catCa = ["Carta alta", "Parella", "Doble parella", "Trio", "Escala", "Color", "Full", "Pòquer", "Escala de color"]
    static let catEn = ["High card", "One pair", "Two pair", "Three of a kind", "Straight", "Flush", "Full house", "Four of a kind", "Straight flush"]
    static func categoria(_ c: Int) -> String { c < 0 || c > 8 ? "" : [catEs, catCa, catEn][Idioma.actual][c] }

    static let sgs = [["dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "jota", "dama", "rey", "as"],
                      ["dos", "tres", "quatre", "cinc", "sis", "set", "vuit", "nou", "deu", "jota", "dama", "rei", "as"],
                      ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "jack", "queen", "king", "ace"]]
    static let pls = [["doses", "treses", "cuatros", "cincos", "seises", "sietes", "ochos", "nueves", "dieces", "jotas", "damas", "reyes", "ases"],
                      ["dosos", "tresos", "quatres", "cincs", "sisos", "sets", "vuits", "nous", "deus", "jotes", "dames", "reis", "asos"],
                      ["twos", "threes", "fours", "fives", "sixes", "sevens", "eights", "nines", "tens", "jacks", "queens", "kings", "aces"]]
    static func sg(_ l: Int, _ v: Int) -> String { v >= 2 && v <= 14 ? sgs[l][v - 2] : "" }
    static func pl(_ l: Int, _ v: Int) -> String { v >= 2 && v <= 14 ? pls[l][v - 2] : "" }
    static func alEs(_ v: Int) -> String { (v == 12 || v == 11 ? "a la " : "al ") + sg(0, v) }
    static func alCa(_ v: Int) -> String { v == 14 ? "a l'as" : (v == 12 || v == 11 ? "a la " : "al ") + sg(1, v) }
    static func deCa(_ x: String) -> String { x.range(of: "^[aeiouàèéíòóúAEIOU]", options: .regularExpression) != nil ? "d'" + x : "de " + x }
    static func may(_ x: String) -> String { x.prefix(1).uppercased() + x.dropFirst() }

    static func nombreMano(_ ev: [Any]?) -> String? {
        guard let ev = ev, ev.count >= 2 else { return nil }
        let cat = num(ev[0]) ?? -1
        let rk = ev[1] as? [Any] ?? []
        let r0 = rk.count > 0 ? num(rk[0]) ?? 0 : 0, r1 = rk.count > 1 ? num(rk[1]) ?? 0 : 0
        switch Idioma.actual {
        case 0:
            if cat < 0 { return "Sin cartas" }
            switch cat {
            case 8: return r0 == 14 ? "ESCALERA REAL" : "Escalera de color " + alEs(r0)
            case 7: return "Póker de " + pl(0, r0)
            case 6: return "Full de " + pl(0, r0) + " y " + pl(0, r1)
            case 5: return "Color " + alEs(r0)
            case 4: return "Escalera " + alEs(r0)
            case 3: return "Trío de " + pl(0, r0)
            case 2: return "Doble pareja de " + pl(0, r0) + " y " + pl(0, r1)
            case 1: return "Pareja de " + pl(0, r0)
            default: return "Carta alta: " + sg(0, r0)
            }
        case 1:
            if cat < 0 { return "Sense cartes" }
            switch cat {
            case 8: return r0 == 14 ? "ESCALA REIAL" : "Escala de color " + alCa(r0)
            case 7: return "Pòquer " + deCa(pl(1, r0))
            case 6: return "Full " + deCa(pl(1, r0)) + " i " + pl(1, r1)
            case 5: return "Color " + alCa(r0)
            case 4: return "Escala " + alCa(r0)
            case 3: return "Trio " + deCa(pl(1, r0))
            case 2: return "Doble parella " + deCa(pl(1, r0)) + " i " + pl(1, r1)
            case 1: return "Parella " + deCa(pl(1, r0))
            default: return "Carta alta: " + sg(1, r0)
            }
        default:
            if cat < 0 { return "No cards" }
            switch cat {
            case 8: return r0 == 14 ? "ROYAL FLUSH" : may(sg(2, r0)) + "-high straight flush"
            case 7: return "Four " + pl(2, r0)
            case 6: return "Full house, " + pl(2, r0) + " over " + pl(2, r1)
            case 5: return may(sg(2, r0)) + "-high flush"
            case 4: return may(sg(2, r0)) + "-high straight"
            case 3: return "Three " + pl(2, r0)
            case 2: return "Two pair, " + pl(2, r0) + " and " + pl(2, r1)
            case 1: return "Pair of " + pl(2, r0)
            default: return may(sg(2, r0)) + " high"
            }
        }
    }

    static func fecha(_ iso: String) -> String {
        guard iso.count >= 10 else { return "" }
        let p = DateFormatter(); p.dateFormat = "yyyy-MM-dd"; p.locale = Locale(identifier: "en_US_POSIX")
        guard let f = p.date(from: String(iso.prefix(10))) else { return iso }
        let o = DateFormatter(); o.locale = Idioma.locale; o.dateStyle = .long
        return o.string(from: f)
    }
    static func euros(_ cent: Int) -> String { cent % 100 == 0 ? "\(cent / 100) €" : String(format: "%.2f €", Double(cent) / 100).replacingOccurrences(of: ".", with: ",") }
    static func miles(_ n: Int) -> String { let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "de_DE"); return f.string(from: NSNumber(value: n)) ?? "\(n)" }
}
