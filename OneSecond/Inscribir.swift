import SwiftUI
import UserNotifications

/// Inscribirse en la TELEMETRÍA GRATUITA de una prueba (Ronda la Llana, Rider 1000) desde la app, sin pasar por la
/// web (como Inscribir.java de Android 1.57): se entra con la cuenta (Apple, Google o correo), se completan los
/// datos que falten (teléfono y moto) y se inscribe. Al acabar, la app se vincula con la inscripción.
/// Se abre al tocar el aviso «Aún puedes inscribirte».
struct InscribirView: View {
    @EnvironmentObject var central: Central
    @EnvironmentObject var cuenta: Cuenta
    @Environment(\.dismiss) var cerrar
    let evId: Int
    let irA: (Prueba) -> Void

    @State private var ev: [String: Any]? = nil
    @State private var usuario: [String: Any]? = nil
    @State private var fase = Fase.cargando
    @State private var campos: [String: String] = [:]
    @State private var estado = ""
    @State private var estadoError = false
    @State private var enviando = false
    @State private var hecho: (dorsal: String, url: String)? = nil
    @State private var entrar = false
    @State private var ayuda = ""
    @State private var entrandoSocial = false

    enum Fase { case cargando, noHay, sinRed, entrar, verificar, datos, hecho }

    private static let claro = Color(hex: 0xC9D3DF), cobre = Color(hex: 0xB8693A), verdeC = Color(hex: 0x7FE0AD)
    private static let lista: [(String, String)] = [
        ("nombre", t("Nombre", "Nom", "First name")), ("apellidos", t("Apellidos", "Cognoms", "Surname")),
        ("telefono", t("Teléfono móvil", "Telèfon mòbil", "Mobile phone")), ("moto", t("Moto (marca y modelo)", "Moto (marca i model)", "Motorcycle (make and model)")),
        ("matricula", t("Matrícula (opcional)", "Matrícula (opcional)", "Number plate (optional)")),
    ]

    var body: some View {
        ZStack {
            TC.fondo.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch fase {
                    case .cargando: Text(t("Cargando…", "Carregant…", "Loading…")).font(.system(size: 15)).foregroundColor(TC.suave).padding(.top, 30)
                    case .noHay: mensaje(t("Telemetría", "Telemetria", "Telemetry"), t("Esta prueba ya no está disponible.", "Aquesta prova ja no està disponible.", "This event is no longer available."), t("Cerrar", "Tancar", "Close")) { cerrar() }
                    case .sinRed: mensaje(t("Sin conexión", "Sense connexió", "No connection"), t("Comprueba los datos móviles o el wifi y vuelve a intentarlo.", "Comprova les dades mòbils o el wifi i torna-ho a provar.", "Check mobile data or wifi and try again."), t("Reintentar", "Tornar-ho a provar", "Retry")) { Task { await cargar() } }
                    case .entrar: pintarEntrar
                    case .verificar: mensaje(t("Confirma tu correo", "Confirma el teu correu", "Confirm your email"), verificarTexto, t("Ya lo he confirmado", "Ja l'he confirmat", "I've confirmed it")) { Task { await cargar() } }
                    case .datos: pintarDatos
                    case .hecho: pintarHecho
                    }
                }.padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 24)
            }
        }
        .task { await cargar() }
        .sheet(isPresented: $entrar, onDismiss: { Task { await cargar() } }) { EntrarView().environmentObject(cuenta).preferredColorScheme(.dark) }
    }

    // ---------- piezas ----------
    private func cabecera(_ titulo: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button { cerrar() } label: { Text("‹").font(.system(size: 30)).foregroundColor(TC.suave) }
                Text(titulo).font(.custom("TeXGyrePagella-Bold", size: 23)).foregroundColor(TC.texto)
            }
            if let e = ev { tarjeta(e) }
        }
    }

    private func tarjeta(_ e: [String: Any]) -> some View {
        let p = Prueba.deCuentas(e.str("app"))
        let pl = e.int("plazas"), oc = e.int("ocupadas")
        return HStack(spacing: 12) {
            Image(p?.icono ?? "ic_ronda").resizable().frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(Cuenta.nombre(e)).font(.custom("TeXGyrePagella-Bold", size: 19)).foregroundColor(TC.texto)
                Text(Self.cuando(e)).font(.system(size: 12.5)).foregroundColor(Self.claro)
                HStack(spacing: 6) {
                    chip(t("Telemetría · gratis", "Telemetria · gratuïta", "Telemetry · free"), Color(hex: 0x0F2A1B), Color(hex: 0x9FE0B4), Color(hex: 0x1F5A3A))
                    if pl > 0 { chip(t("Quedan ", "Queden ", "") + "\(max(0, pl - oc))" + t(" plazas", " places", " places left"), TC.panel, Self.claro, TC.borde) }
                }.padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Color(hex: 0x2C1A10), Color(hex: 0x151B25), TC.panel], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x4A2A16), lineWidth: 1))
    }

    private func chip(_ s: String, _ fondo: Color, _ color: Color, _ borde: Color) -> some View {
        Text(s).font(.system(size: 11.5, weight: .medium)).foregroundColor(color).padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(fondo)).overlay(Capsule().stroke(borde))
    }

    private func boton(_ s: String, _ fondo: Color, _ color: Color, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(s).font(.system(size: 16, weight: .medium)).foregroundColor(color).frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(fondo))
        }
    }

    private func mensaje(_ titulo: String, _ txt: String, _ bt: String, _ al: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecera(titulo)
            Text(txt).font(.system(size: 15)).foregroundColor(Self.claro).padding(.top, 18)
            boton(bt, TC.azul, .white, accion: al).padding(.top, 22)
        }
    }

    private var verificarTexto: String {
        let em = usuario?.str("email") ?? ""
        return t("Antes de inscribirte tienes que confirmar tu correo (" + em + "): te enviamos un enlace al crear la cuenta. Cuando lo hayas confirmado, vuelve aquí.",
                 "Abans d'inscriure't has de confirmar el teu correu (" + em + "): et vam enviar un enllaç en crear el compte. Quan l'hagis confirmat, torna aquí.",
                 "Before signing up you need to confirm your email (" + em + "): we sent you a link when you created the account. Come back once confirmed.")
    }

    // ---------- sin cuenta: Apple, Google o correo ----------
    private var pintarEntrar: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecera(t("Inscribirte en la telemetría", "Inscriure't a la telemetria", "Sign up for telemetry"))
            Text(t("La telemetría es gratis. Para inscribirte necesitas una cuenta de One Second: con Apple o Google es un toque.",
                   "La telemetria és gratuïta. Per inscriure't necessites un compte de One Second: amb Apple o Google és un toc.",
                   "Telemetry is free. To sign up you need a One Second account: with Apple or Google it takes one tap."))
                .font(.system(size: 14.5)).foregroundColor(Self.claro).padding(.top, 18)
            BotonesSociales(ayuda: $ayuda, entrando: $entrandoSocial) { Task { await cargar() } }.padding(.top, 16)
            if !ayuda.isEmpty { Text(ayuda).font(.footnote).foregroundColor(TC.naranja).padding(.top, 8) }
            Button { entrar = true } label: {
                Text(t("Entrar con mi correo", "Entrar amb el meu correu", "Sign in with my email")).font(.system(size: 16, weight: .medium)).foregroundColor(Self.claro)
                    .frame(maxWidth: .infinity).frame(height: 52).overlay(RoundedRectangle(cornerRadius: 14).stroke(TC.borde))
            }.padding(.top, 10)
            Text(t("¿No tienes cuenta? Con Apple o Google se crea sola.", "No tens compte? Amb Apple o Google es crea sol.", "No account? With Apple or Google it's created for you."))
                .font(.system(size: 12.5)).foregroundColor(TC.suave).frame(maxWidth: .infinity).padding(.top, 14)
        }
    }

    // ---------- con cuenta: los datos que se usarán (y los que faltan) ----------
    private func u(_ k: String) -> String {
        let v = usuario?.str(k) ?? ""
        return v == "null" ? "" : v.trimmingCharacters(in: .whitespaces)
    }
    private var entradoComo: String {
        let a = t("Has entrado como ", "Has entrat com a ", "Signed in as ")
        let b = t(". Solo faltan estos datos:", ". Només falten aquestes dades:", ". Just these details are missing:")
        return a + u("email") + b
    }
    private var falta: Bool { Self.lista.prefix(4).contains { u($0.0).isEmpty } }

    private var pintarDatos: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecera(t("Inscribirte en la telemetría", "Inscriure't a la telemetria", "Sign up for telemetry"))
            if falta {
                Text(entradoComo)
                    .font(.system(size: 14)).foregroundColor(Self.claro).padding(.top, 18)
                ForEach(Self.lista.filter { u($0.0).isEmpty }, id: \.0) { c in
                    Text(c.1).font(.system(size: 12.5)).foregroundColor(TC.suave).padding(.top, 12)
                    TextField("", text: Binding(get: { campos[c.0] ?? "" }, set: { campos[c.0] = $0 }))
                        .keyboardType(c.0 == "telefono" ? .phonePad : .default)
                        .textInputAutocapitalization(.words)
                        .font(.system(size: 16)).foregroundColor(TC.texto).padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0F141C)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TC.borde)).padding(.top, 5)
                }
            } else {
                Text(t("CON LOS DATOS DE TU CUENTA", "AMB LES DADES DEL TEU COMPTE", "WITH YOUR ACCOUNT DETAILS")).font(.system(size: 10.5, weight: .medium))
                    .tracking(1.7).foregroundColor(TC.suave).padding(.top, 18)
                fila(t("Nombre", "Nom", "Name"), (u("nombre") + " " + u("apellidos")).trimmingCharacters(in: .whitespaces))
                fila(t("Teléfono", "Telèfon", "Phone"), u("telefono"))
                fila(t("Moto", "Moto", "Motorcycle"), u("moto"))
                if !u("matricula").isEmpty { fila(t("Matrícula", "Matrícula", "Plate"), u("matricula")) }
            }
            Text(t("Al inscribirte, el día de la prueba la app enviará tu posición a la organización al abrirla. Puedes pararlo cuando quieras.",
                   "En inscriure't, el dia de la prova l'app enviarà la teva posició a l'organització en obrir-la. Ho pots aturar quan vulguis.",
                   "Once signed up, on the day the app will share your position with the organisers when you open it. You can stop it any time."))
                .font(.system(size: 12.5)).foregroundColor(TC.suave).padding(.top, 16)
            if !estado.isEmpty { Text(estado).font(.system(size: 13.5)).foregroundColor(estadoError ? TC.rojo : TC.suave).padding(.top, 10) }
            boton("✓  " + t("Inscribirme en la telemetría", "Inscriure'm a la telemetria", "Sign me up for telemetry"), Self.cobre, .white) { Task { await inscribir() } }
                .disabled(enviando).opacity(enviando ? 0.6 : 1).padding(.top, 8)
            if !falta {
                Button(t("Cambiar mis datos", "Canviar les meves dades", "Change my details")) {
                    if let u = URL(string: Cuenta.base + "/?lang=" + Idioma.codigo) { UIApplication.shared.open(u) }
                }.font(.system(size: 14, weight: .medium)).foregroundColor(Color(hex: 0x8FBAF0)).frame(maxWidth: .infinity).padding(.top, 14)
            }
        }
    }

    private func fila(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            HStack { Text(k).font(.system(size: 14)).foregroundColor(TC.suave); Spacer(); Text(v).font(.system(size: 14, weight: .medium)).foregroundColor(TC.texto) }
                .padding(.vertical, 10)
            Rectangle().fill(Color(hex: 0x222C3B)).frame(height: 1)
        }
    }

    // ---------- hecho ----------
    private var pintarHecho: some View {
        let p = ev.flatMap { Prueba.deCuentas($0.str("app")) }
        return VStack(spacing: 0) {
            Text("✓").font(.custom("TeXGyrePagella-Bold", size: 40)).foregroundColor(Self.verdeC).frame(width: 84, height: 84)
                .background(Circle().fill(Color(hex: 0x173326))).overlay(Circle().stroke(TC.verde, lineWidth: 1.5)).padding(.top, 40)
            Text(t("TELEMETRÍA · INSCRIPCIÓN HECHA", "TELEMETRIA · INSCRIPCIÓ FETA", "TELEMETRY · YOU'RE SIGNED UP")).font(.system(size: 12.5, weight: .medium))
                .tracking(1.2).foregroundColor(Self.verdeC).padding(.top, 16)
            if let d = hecho?.dorsal, !d.isEmpty { Text(t("Dorsal ", "Dorsal ", "No. ") + d).font(.custom("TeXGyrePagella-Bold", size: 28)).foregroundColor(TC.texto) }
            if let e = ev { Text(Cuenta.nombre(e) + " · " + Self.cuando(e)).font(.system(size: 14)).foregroundColor(Self.claro).multilineTextAlignment(.center) }
            Text(Self.infoHecho)
                .font(.system(size: 13.5)).foregroundColor(Self.claro).lineSpacing(3).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(TC.panel)).overlay(RoundedRectangle(cornerRadius: 14).stroke(TC.borde)).padding(.top, 24)
            boton(t("Ir a ", "Anar a ", "Go to ") + (p?.nombre ?? "One Second"), TC.azul, .white) {
                cerrar()
                if let p = p { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { irA(p) } }
            }.padding(.top, 22)
        }
    }

    // ---------- servidor ----------
    private func cargar() async {
        fase = .cargando
        ev = Cuenta.shared.eventos.first { $0.int("id") == evId }
        if ev == nil { await cuenta.actualizar(); ev = Cuenta.shared.eventos.first { $0.int("id") == evId } }
        var sinRed = false
        usuario = nil
        if cuenta.conectado {
            let r = await Cuenta.pedir("GET", "/api/yo", token: cuenta.token)
            if r.codigo == -1 { sinRed = true }
            usuario = r.json["usuario"] as? [String: Any]
        }
        if ev == nil { fase = .noHay }
        else if sinRed { fase = .sinRed }
        else if usuario == nil { fase = .entrar }
        else if !(usuario?.bool("verificado") ?? false) { fase = .verificar }
        else { fase = .datos }
    }

    private func inscribir() async {
        var perfil: [String: Any]? = nil
        if falta {
            var p: [String: Any] = [:]
            for k in ["nombre", "apellidos", "telefono", "moto", "matricula", "motoclub", "emergencia_nombre", "emergencia_telefono"] { p[k] = u(k) }
            for (i, c) in Self.lista.enumerated() where u(c.0).isEmpty {
                let v = (campos[c.0] ?? "").trimmingCharacters(in: .whitespaces)
                if v.isEmpty && i < 4 { estado = t("Rellena: ", "Omple: ", "Please fill in: ") + c.1.lowercased(); estadoError = true; return }
                p[c.0] = v
            }
            p["idioma"] = Idioma.codigo
            perfil = p
        }
        enviando = true; estadoError = false; estado = t("Inscribiendo…", "Inscrivint…", "Signing up…")
        var err: String? = nil
        if let pf = perfil {
            let r = await Cuenta.pedir("PUT", "/api/perfil", cuerpo: pf, token: cuenta.token)
            if r.codigo != 200 { err = r.codigo == -1 ? "sin_red" : (r.json.str("codigo").isEmpty ? "perfil" : r.json.str("codigo")) }
        }
        var dorsal = "", url = ""
        if err == nil {
            let r = await Cuenta.pedir("POST", "/api/inscripciones", cuerpo: ["evento_id": evId], token: cuenta.token)
            let cod = r.json.str("codigo")
            if r.codigo != 200 && cod != "ya_inscrito" { err = r.codigo == -1 ? "sin_red" : (cod.isEmpty ? "error" : cod) }
            else {
                dorsal = (r.json["inscripcion"] as? [String: Any])?.str("dorsal_txt") ?? ""
                cuenta.marcarInscrita(evId)
                let m = await Cuenta.pedir("GET", "/api/mis_inscripciones", token: cuenta.token)
                for o in m.json["inscripciones"] as? [[String: Any]] ?? [] where o.int("evento_id") == evId && o.str("tipo") != "aficionado" {
                    if dorsal.isEmpty { dorsal = o.str("dorsal_txt").isEmpty ? o.str("dorsal") : o.str("dorsal_txt") }
                    let g = o.str("gps_app"); url = g == "null" ? "" : g
                }
            }
        }
        enviando = false
        if let e = err {
            estadoError = true
            switch e {
            case "sin_red": estado = t("Sin conexión. Vuelve a intentarlo.", "Sense connexió. Torna-ho a provar.", "No connection. Try again.")
            case "evento_cerrado": estado = t("Las inscripciones a la telemetría ya están cerradas.", "Les inscripcions a la telemetria ja estan tancades.", "Telemetry sign-ups are closed.")
            case "evento_completo": estado = t("Ya no quedan plazas.", "Ja no queden places.", "No places left.")
            case "sin_verificar": estado = t("Primero confirma tu correo.", "Primer confirma el teu correu.", "Confirm your email first.")
            default: estado = t("No se ha podido inscribir (" + e + "). Prueba desde onesecond.es.", "No s'ha pogut inscriure (" + e + "). Prova des d'onesecond.es.", "Could not sign up (" + e + "). Try at onesecond.es.")
            }
            return
        }
        // la app se vincula con la inscripción (si no estaba vinculada a otra cosa)
        if !url.isEmpty, let p = Prueba.deQuien(url), !central.aj(p).vinculada, central.emitiendo == nil { _ = central.vincular(p, url: url) }
        hecho = (dorsal, url)
        fase = .hecho
    }

    static var infoHecho: String {
        let a = "✉  " + t("Te hemos enviado el correo de confirmación.", "T'hem enviat el correu de confirmació.", "We've sent you the confirmation email.")
        let b = "🔗  " + t("La app se vincula con tu inscripción.", "L'app es vincula amb la teva inscripció.", "The app links to your sign-up.")
        let c = "📡  " + t("El día de la prueba, al abrir la app, emitirá tu posición sola.", "El dia de la prova, en obrir l'app, emetrà la teva posició sola.", "On the day, the app will share your position by itself when you open it.")
        return a + "\n" + b + "\n" + c
    }

    static func cuando(_ e: [String: Any]) -> String {
        guard let s = Cuenta.salida(e) else { return "" }
        let f = DateFormatter(); f.locale = Idioma.locale; f.timeZone = Cuenta.madrid; f.dateFormat = "EEEE d"
        let h = DateFormatter(); h.timeZone = Cuenta.madrid; h.dateFormat = "HH:mm"
        let l = Cuenta.lugar(e)
        var d = f.string(from: s) + " · " + h.string(from: s)
        if !l.isEmpty { d += " · " + l }
        return d.prefix(1).uppercased() + d.dropFirst()
    }
}

/// Los avisos de las pruebas: se ven también con la app abierta, y al tocar «Aún puedes inscribirte» se abre
/// la inscripción en la telemetría.
final class Avisador: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Avisador()
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler fin: @escaping (UNNotificationPresentationOptions) -> Void) {
        fin([.banner, .sound, .list])
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler fin: @escaping () -> Void) {
        let i = r.notification.request.content.userInfo
        if let j = i["minijuego"] as? String {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NotificationCenter.default.post(name: .abrirMiniJuego, object: [j, BingoAvisos.web]) }
        }
        if let id = i["evento"] as? Int {
            let ins = i["inscribir"] as? Bool ?? false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotificationCenter.default.post(name: ins ? .abrirInscribir : .abrirPruebaDe, object: ins ? id as Any : (i["app"] as? String ?? "") as Any)
            }
        }
        fin()
    }
}

final class AppDelegado: NSObject, UIApplicationDelegate {
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = Avisador.shared
        return true
    }
}

extension Notification.Name {
    static let abrirInscribir = Notification.Name("abrirInscribir")
    static let abrirPruebaDe = Notification.Name("abrirPruebaDe")
}
