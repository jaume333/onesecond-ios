import SwiftUI

/// One Second Rally: la misma pantalla que en Android 1.57 (MainActivity). La bandera a cuadros con el logo, el
/// nombre en plata y el lema; tu posición provisional (como «Ver mis tiempos» de la web); emitir / parar
/// (Parar manteniendo pulsado); avisos; caída / accidente; mis avisos; la clasificación de los 25 primeros
/// (tocando un piloto, el desglose de sus tiempos) y ajustes.
struct RallyView: View {
    @EnvironmentObject var central: Central
    @Environment(\.dismiss) var volver
    let p: Prueba
    @State private var hoja: Hoja? = nil
    @State private var aviso: String? = nil
    @State private var confirmarAccidente = false
    @State private var llamar = false
    @State private var posJson: [String: Any]? = nil
    @State private var posPedida = Date.distantPast
    @State private var clas: [String: Any]? = nil
    @State private var clasCodigo = 0
    @State private var tiemposDe: FilaClas? = nil
    private let reloj = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let relojClas = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    enum Hoja: String, Identifiable { case vincular, chat, ajustes; var id: String { rawValue } }
    struct FilaClas: Identifiable { let id = UUID(); let x: [String: Any] }

    private static let oro = Color(hex: 0xD4A72C), claro = Color(hex: 0xC9D3DF), panel2 = Color(hex: 0x18202C)
    private static let cromado = [0xFFFFFF, 0xE3E9F1, 0xAEB7C2, 0xF1F4F8, 0xC9D1DB].map { Color(hex: $0) }

    var body: some View {
        let _ = central.tick
        let aj = central.aj(p)
        ZStack(alignment: .top) {
            TC.fondo.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    cabecera
                    VStack(spacing: 0) {
                        if !aj.vinculada { vincularBloque.padding(.top, 14) }
                        else { tarjeta.padding(.top, 16) }
                        let ex = extra()
                        if !ex.0.isEmpty {
                            Text(ex.0).font(.system(size: 12.5)).foregroundColor(ex.1 ? TC.naranja : TC.suave)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 8)
                        }
                        if aj.vinculada {
                            MensajesCaja(p: p, tx: TxRally.t, acento: Self.oro, boton: TC.azul, botonTexto: .white,
                                         burbuja: Color(hex: 0x1D3550), burbujaB: Color(hex: 0x2C5A86)) { hoja = .chat }.padding(.top, 14)
                        }
                        emitirBloque.padding(.top, 12)
                        avisar.padding(.top, 16)
                    }.padding(.horizontal, 16).padding(.bottom, 16)
                    VStack(spacing: 0) {
                        MisAvisos(p: p)
                        Text(TxRally.t("clas_t").uppercased()).font(.system(size: 11, weight: .bold)).tracking(2).foregroundColor(TC.suave)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20)
                        clasificacion.padding(.top, 8)
                        Button { hoja = .ajustes } label: {
                            Text("⚙  " + TxRally.t("ajustes")).font(.system(size: 15, weight: .bold)).foregroundColor(Self.claro)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(RoundedRectangle(cornerRadius: 8).fill(TC.fondo))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TC.borde, lineWidth: 1.5))
                        }.padding(.top, 14)
                        Text(TxRally.t("ayuda")).font(.system(size: 13)).foregroundColor(TC.suave).multilineTextAlignment(.center).padding(.top, 14)
                    }.padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
            Button { volver() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundColor(TC.texto)
                    .frame(width: 40, height: 40).background(Circle().fill(TC.fondo.opacity(0.88)))
                    .overlay(Circle().stroke(TC.borde, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).padding(.top, 6)
            if let f = tiemposDe {
                Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { tiemposDe = nil }
                FichaTiemposRally(x: f.x, web: web) { tiemposDe = nil }
            }
            Breve()
        }
        .navigationBarHidden(true)
        .onAppear {
            if Demo.activo {
                if Demo.pantalla == 5 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { hoja = .vincular } } else { cargarDemo() }
                return
            }
            pedirPosicion()
            Task { await cargarClas() }
        }
        .onReceive(reloj) { _ in pedirPosicion() }
        .onReceive(relojClas) { _ in Task { await cargarClas() } }
        .sheet(item: $hoja) { h in
            Group {
                switch h {
                case .vincular: VincularView(p: p)
                case .chat: ChatView(p: p)
                case .ajustes: AjustesView(p: p, vincular: { hoja = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { hoja = .vincular } })
                }
            }
            .environmentObject(central).environmentObject(Cuenta.shared).preferredColorScheme(.dark)
        }
        .sheet(item: Binding(get: { aviso.map { AvisoTipo(tipo: $0) } }, set: { aviso = $0?.tipo })) { a in
            PanelAviso(p: p, tipo: a.tipo, acento: TC.azul) { aviso = nil }.environmentObject(central).preferredColorScheme(.dark)
        }
        .alert(t("¿Has tenido una caída o un accidente?", "Has tingut una caiguda o un accident?", "Have you had a crash or an accident?"), isPresented: $confirmarAccidente) {
            Button(t("Sí, enviar aviso", "Sí, enviar avís", "Yes, send alert"), role: .destructive) { enviarAccidente(); llamar = true }
            Button(t("Cancelar", "Cancel·lar", "Cancel"), role: .cancel) {}
        } message: {
            Text(t("Se avisa a la organización con tu posición.", "S'avisa l'organització amb la teva posició.", "The organisers are alerted with your position."))
        }
        .confirmationDialog(t("¿Llamar?", "Trucar?", "Call?"), isPresented: $llamar, titleVisibility: .visible) {
            Button("📞 112") { Llamar.a("112") }
            if !aj.telOrg.isEmpty { Button("📞 " + TxRally.t("organizacion") + " · " + aj.telOrg) { Llamar.a(aj.telOrg) } }
            Button(t("Ahora no", "Ara no", "Not now"), role: .cancel) {}
        }
    }

    // ---------- bandera a cuadros con el logo encima ----------
    private var cabecera: some View {
        ZStack(alignment: .top) {
            BanderaCuadros().frame(height: 150)
            VStack(spacing: 0) {
                Image("logo_ros_aro").resizable().scaledToFit().frame(width: 146, height: 146).clipShape(Circle())
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
                let n = Text("One Second Rally").font(.custom("TeXGyrePagella-Bold", size: 36))
                n.lineLimit(1).minimumScaleFactor(0.6).foregroundColor(.clear)
                    .overlay(LinearGradient(stops: zip(Self.cromado, [0, 0.4, 0.55, 0.75, 1.0]).map { .init(color: $0, location: $1) }, startPoint: .top, endPoint: .bottom)
                        .mask(n.lineLimit(1).minimumScaleFactor(0.6)))
                    .padding(.top, 6)
                (Text(TxRally.t("lema_a")).italic().foregroundColor(Self.claro)
                 + Text(TxRally.t("lema_b")).font(.custom("TeXGyrePagella-Bold", size: 13.5)).foregroundColor(TC.texto)
                 + Text(".»").italic().foregroundColor(Self.claro))
                    .font(.system(size: 13.5)).multilineTextAlignment(.center).padding(.top, 2)
            }
            .padding(.horizontal, 16).padding(.top, 22)
        }
    }

    private var vincularBloque: some View {
        VStack(spacing: 2) {
            Button { hoja = .vincular } label: {
                Text("🔗  " + TxRally.t("vincular_ins")).font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: 0x7FB2F0))
                    .frame(minHeight: 44).padding(.horizontal, 16)
            }
            Text(TxRally.t("vincular_sub")).font(.system(size: 12.5)).foregroundColor(TC.suave).multilineTextAlignment(.center)
        }.padding(.top, 4).padding(.bottom, 2)
    }

    // ---------- posición provisional (tarjeta dorada, como el primero del podio de la web) ----------
    private var tarjeta: some View {
        let aj = central.aj(p)
        let on = central.emitiendo(p)
        let hace = central.ultimaPos.map { Int(Date().timeIntervalSince($0)) } ?? -1
        let (est, colorEst): (String, Color) = !on ? (TxRally.t("st_parado"), Color(hex: 0x3A4558))
            : hace < 0 ? (TxRally.t("st_gps"), TC.naranja)
            : (TxRally.t("st_emitiendo"), hace <= central.gpsActual(p) + 5 ? TC.verde : TC.naranja)
        var pos = "—", pen = "—", nombre = aj.nombrePiloto, meta = false
        var sub = aj.dorsal.isEmpty ? "" : TxRally.f("sin_pasos", aj.dorsal)
        if let o = posJson, o["pos"] is NSNumber {
            pos = "\(o.int("pos"))º"
            pen = Self.penTexto(o.str("pen"))
            let cs = o["controles"] as? [[String: Any]] ?? []
            let hechos = cs.filter { $0.int("t") > 0 || !($0.str("hora").isEmpty || $0.str("hora") == "null") }.count
            meta = o.str("estado") == "Finalizado"
            sub = TxRally.f("controles_n", aj.dorsal, hechos, cs.count) + (meta ? " · " + TxRally.t("en_meta") : "")
            if !o.str("nombre").isEmpty { nombre = o.str("nombre") }
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(TxRally.t(meta ? "pos_final" : "posicion").uppercased()).font(.system(size: 11, weight: .bold)).tracking(2.2).foregroundColor(Self.oro)
                Spacer()
                Text("● " + est).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(colorEst))
            }
            HStack(alignment: .center, spacing: 0) {
                Group {
                    if pos.hasSuffix("º") {
                        Text(String(pos.dropLast())).font(.custom("TeXGyrePagella-Bold", size: 52)) + Text("º").font(.custom("TeXGyrePagella-Bold", size: 23))
                    } else { Text(pos).font(.custom("TeXGyrePagella-Bold", size: 52)) }
                }.foregroundColor(Self.oro)
                VStack(alignment: .leading, spacing: 1) {
                    Text(nombre).font(.custom("TeXGyrePagella-Bold", size: 19)).foregroundColor(TC.texto).lineLimit(1)
                    Text(sub).font(.system(size: 12.5)).foregroundColor(TC.suave)
                }.padding(.horizontal, 12)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(TxRally.t("penalizacion").uppercased()).font(.system(size: 10)).tracking(1.2).foregroundColor(TC.suave)
                    Text(pen).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(TC.texto)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Color(hex: 0x2A2412), Color(hex: 0x151B25), TC.panel], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x3A3214), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    private func extra() -> (String, Bool) {
        guard central.emitiendo(p) else { return ("", false) }
        var l: [String] = []
        let hace = central.ultimaPos.map { Int(Date().timeIntervalSince($0)) } ?? -1
        let g = central.gpsActual(p)
        if hace < 0 { l.append(TxRally.t("esperando_gps")) }
        else {
            l.append(hace < 120 ? TxRally.f("hace_s", hace, Int(central.ultimaPrec.rounded())) : TxRally.f("hace_min", hace / 60, Int(central.ultimaPrec.rounded())))
            if g >= 60 { l.append(TxRally.f("modo_seg", g / 60)) }
        }
        if central.pendientes > 3 { l.append(TxRally.f("pendientes", central.pendientes)) }
        if central.codigoMal { l.append(TxRally.t("error_codigo")) } else if central.sinRed { l.append(TxRally.t("sin_red")) }
        if central.falso { l.append(TxRally.t("falso")) }
        return (l.joined(separator: "  ·  "), central.codigoMal || central.falso || central.sinRed)
    }

    // ---------- emitir / parar (Parar manteniendo pulsado 1,5 s) ----------
    @ViewBuilder private var emitirBloque: some View {
        let aj = central.aj(p)
        if central.emitiendo(p) {
            BotonMantener(arriba: "■  " + TxRally.t("parar_b"), abajo: TxRally.t("mantener"), alAcabar: { central.parar() },
                          antes: { central.breve(TxRally.t("mantener_aviso"), error: true) }, dura: 1.5)
                .frame(maxWidth: .infinity).frame(height: 56)
        } else {
            VStack(spacing: 10) {
                Text(TxRally.t("parado_desc")).font(.system(size: 13)).foregroundColor(TC.suave).multilineTextAlignment(.center)
                let otra = central.emitiendo != nil
                Button { if aj.vinculada { central.emitir(p) } else { hoja = .vincular } } label: {
                    Text("▶  " + TxRally.t("emitir_b")).font(.system(size: 19, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 56).background(RoundedRectangle(cornerRadius: 12).fill(TC.azul))
                }.disabled(otra).opacity(otra ? 0.4 : 1)
                if otra {
                    Text(t("Se está emitiendo en otra prueba. Páralo allí antes.", "S'està emetent en una altra prova. Atura-ho allà abans.", "Another event is sending. Stop it there first."))
                        .font(.system(size: 13)).foregroundColor(TC.naranja)
                }
            }
        }
    }

    // ---------- avisar a la organización: 3 x 2 botones, caída / accidente y llamar ----------
    private var avisar: some View {
        let tipos = ["pinchazo", "averia", "gasolina", "perdido", "abandono", "otro"]
        let tel = central.aj(p).telOrg
        return VStack(spacing: 9) {
            Text(TxRally.t("avisar").uppercased()).font(.system(size: 11, weight: .bold)).tracking(2.4).foregroundColor(TC.suave)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
            ForEach(0..<2) { fi in
                HStack(spacing: 9) {
                    ForEach(0..<3) { k in
                        let tipo = tipos[fi * 3 + k]
                        Button { aviso = tipo } label: {
                            VStack(spacing: 2) {
                                Text(Avisos.icono(tipo)).font(.system(size: 21))
                                Text(TelemetriaView.nombreCorto(tipo)).font(.system(size: 13.5, weight: .bold)).foregroundColor(Self.claro).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).frame(height: 70)
                            .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Self.panel2, TC.panel], startPoint: .top, endPoint: .bottom)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(TC.borde, lineWidth: 1))
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button { confirmarAccidente = true } label: {
                    Text("⚠  " + TxRally.t("av_accidente")).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 60).background(RoundedRectangle(cornerRadius: 8).fill(TC.rojo))
                }
                if !tel.isEmpty {
                    Button { Llamar.a(tel) } label: {
                        Text("📞").font(.system(size: 18)).frame(width: 72, height: 60)
                            .background(RoundedRectangle(cornerRadius: 8).fill(TC.fondo))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(TC.borde, lineWidth: 1.5))
                    }
                }
            }.padding(.top, 5)
        }
    }

    // ---------- clasificación · los 25 primeros (la de la web pública; cada 30 s) ----------
    @ViewBuilder private var clasificacion: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let j = clas {
                let ev = j["event"] as? [String: Any]
                HStack {
                    Text(ev?.str("name") ?? "One Second Rally").font(.custom("TeXGyrePagella-Bold", size: 16)).foregroundColor(TC.texto).lineLimit(1)
                    Spacer()
                    Text(j.bool("final") ? TxRally.t("clas_final") : "● " + TxRally.t("clas_directo")).font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(j.bool("final") ? Self.oro : TC.verde)
                }
                let top = j["top"] as? [[String: Any]] ?? []
                if top.isEmpty {
                    Text(TxRally.t("clas_vacia")).font(.system(size: 13.5)).foregroundColor(TC.suave).padding(.top, 8)
                } else {
                    let mio = Self.sinCeros(central.aj(p).dorsal)
                    let vinc = central.aj(p).vinculada
                    ForEach(Array(top.prefix(25).enumerated()), id: \.offset) { k, x in
                        filaClas(x, yo: vinc && !mio.isEmpty && mio == Self.sinCeros(x.str("dorsal")))
                            .contentShape(Rectangle()).onTapGesture { tiemposDe = FilaClas(x: x) }
                            .padding(.top, k == 0 ? 10 : 2)
                    }
                }
                Button { if let u = URL(string: "https://onesecond.es" + web) { UIApplication.shared.open(u) } } label: {
                    Text(TxRally.t("clas_completa") + "  ↗").font(.system(size: 15, weight: .bold)).foregroundColor(TC.texto)
                        .frame(maxWidth: .infinity).frame(height: 48).background(RoundedRectangle(cornerRadius: 8).fill(Self.panel2))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TC.borde, lineWidth: 1.5))
                }.padding(.top, 14)
                Text(TxRally.t("clas_abre") + " onesecond.es" + web.replacingOccurrences(of: "/$", with: "", options: .regularExpression))
                    .font(.system(size: 12)).foregroundColor(TC.suave).frame(maxWidth: .infinity).padding(.top, 6)
            } else {
                Text(TxRally.t(clasCodigo == 0 ? "clas_cargando" : clasCodigo == 503 || clasCodigo == 429 ? "clas_mucha" : "clas_error"))
                    .font(.system(size: 14)).foregroundColor(TC.suave)
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(TC.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(TC.borde, lineWidth: 1.5))
    }

    private func filaClas(_ x: [String: Any], yo: Bool) -> some View {
        let pos = x.int("pos")
        return HStack(spacing: 0) {
            Text(pos > 0 ? "\(pos)" : "–").font(.system(size: 14, weight: .bold)).foregroundColor(pos > 0 && pos <= 3 ? Self.oro : Self.claro)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(x.str("nombre") + "  #" + Self.sinCeros(x.str("dorsal"))).font(.system(size: 13.5, weight: .bold)).foregroundColor(TC.texto).lineLimit(1)
                Text(x.str("ultimo") + (x.str("estado").isEmpty ? "" : " · " + x.str("estado"))).font(.system(size: 12)).foregroundColor(TC.suave).lineLimit(1)
            }.padding(.horizontal, 10)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(x.str("pen")).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                Text(x.str("dif")).font(.system(size: 11)).foregroundColor(pos == 1 ? Self.oro : TC.suave)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(yo ? TC.azul.opacity(0.14) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(yo ? TC.azul.opacity(0.55) : .clear, lineWidth: 1.5))
    }

    // ---------- datos ----------
    /// La web de la prueba del piloto: lo que va antes de /api/p/ en su dirección (/rally/, /rallypoker/...).
    private var web: String {
        let u = central.aj(p).url
        if let r = u.range(of: #"^https://(?:www\.)?onesecond\.es(/[A-Za-z0-9_./-]*?/)api/p/"#, options: .regularExpression) {
            let s = String(u[r])
            if let a = s.range(of: "onesecond.es"), let b = s.range(of: "api/p/") { return String(s[a.upperBound..<b.lowerBound]) }
        }
        return "/rally/"
    }

    private static var idVisita: String {
        if let v = UserDefaults.standard.string(forKey: "prueba_web_vid") { return v }
        let v = "app" + String(UInt64.random(in: 1...UInt64.max), radix: 36)
        UserDefaults.standard.set(v, forKey: "prueba_web_vid")
        return v
    }

    /// Lo mismo que «Ver mis tiempos» de la web pública; como mucho una vez por minuto.
    private func pedirPosicion() {
        let aj = central.aj(p)
        guard aj.vinculada, !aj.dorsal.isEmpty, Date().timeIntervalSince(posPedida) > 60 else { return }
        posPedida = Date()
        let dor = aj.dorsal.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let u = "https://onesecond.es" + web + "api/public/live/participante?d=" + dor
        Task {
            let (c, d) = await Red.pedir(u)
            if c == 200 { posJson = Red.objeto(d) } else if c == 404 { posJson = [:] }
        }
    }

    private func cargarClas() async {
        let (c, d) = await Red.pedir("https://onesecond.es" + web + "api/public/live?v=" + Self.idVisita)
        clasCodigo = c
        if c >= 200 && c < 300 { clas = Red.objeto(d) }
    }

    private func enviarAccidente() {
        var pos: (Double, Double, Double)? = nil
        if let l = central.ultimaLocalizacion { pos = (l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy) }
        central.avisos(p).nuevo(tipo: "accidente", texto: "", pos: pos)
        central.rafaga()
        Task { await central.avisos(p).sincronizar(); central.tick += 1 }
    }

    private func cargarDemo() {
        posJson = ["pos": 4, "pen": "0:07.4", "nombre": "Jaume Garcia", "estado": "En carrera",
                   "controles": [["t": 1], ["t": 1], ["t": 1], ["t": 0], ["t": 0]]]
        let nombres = ["Sergi Serra", "Cristina Torres", "Eva Navarro", "Jaume Garcia", "Oriol Puig", "Marta Vidal", "Pau Roca"]
        clas = ["event": ["name": "One Second Rally · Simulación"], "final": false,
                "top": nombres.enumerated().map { i, n in ["pos": i + 1, "nombre": n, "dorsal": "\([25, 44, 35, 27, 41, 12, 8][i])",
                                                           "ultimo": "CH\(3 + (i % 2))", "pen": String(format: "0:%02d.%d", 2 + i, i * 3 % 10), "dif": i == 0 ? "Líder" : "+\(i).\(i * 2 % 10)"] }]
        central.aj(p).dorsal = "27"
    }

    static func sinCeros(_ s: String) -> String { s.replacingOccurrences(of: "^0+(?=\\d)", with: "", options: .regularExpression) }

    /// «0:02.3» -> «2,3 s»; con minutos se deja como viene (1:12.4).
    static func penTexto(_ s: String) -> String {
        if s.isEmpty || s == "-" || s == "null" { return "—" }
        if let r = s.range(of: #"^0:(\d\d)\.(\d)$"#, options: .regularExpression), r.lowerBound == s.startIndex {
            let seg = Int(s.dropFirst(2).prefix(2)) ?? 0, dec = s.suffix(1)
            return "\(seg)" + (Idioma.actual == 2 ? "." : ",") + dec + " s"
        }
        return s
    }
}

private struct AvisoTipo: Identifiable { let tipo: String; var id: String { tipo } }

/// La ventana con el desglose de tiempos de un piloto en cada control (como la ventana emergente de la web).
struct FichaTiemposRally: View {
    let x: [String: Any]
    let web: String
    let cerrar: () -> Void
    @State private var det: [String: Any]? = nil
    @State private var error = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(x.str("nombre")).font(.custom("TeXGyrePagella-Bold", size: 21)).foregroundColor(TC.texto)
                Text("Dorsal " + RallyView.sinCeros(x.str("dorsal")) + (x.str("motoclub").isEmpty ? "" : " · " + x.str("motoclub"))
                     + (x.str("moto").isEmpty ? "" : " · " + x.str("moto"))).font(.system(size: 12.5)).foregroundColor(TC.suave).padding(.top, 3)
                Group {
                    if let d = det { TiemposVista(det: d) }
                    else if error { Text(TxRally.t("clas_det_error")).font(.system(size: 14)).foregroundColor(TC.naranja) }
                    else { Text(TxRally.t("clas_cargando_t")).font(.system(size: 14)).foregroundColor(TC.suave) }
                }.padding(.top, 14)
                Button(action: cerrar) {
                    Text(TxRally.t("cerrar")).font(.system(size: 15, weight: .bold)).foregroundColor(TC.texto)
                        .frame(maxWidth: .infinity).frame(height: 48).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x18202C)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TC.borde, lineWidth: 1.5))
                }.padding(.top, 16)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(TC.panel))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0x2B3648), lineWidth: 1))
            .padding(14).padding(.top, 60)
        }
        .task {
            if Demo.activo { error = true; return }
            let dor = x.str("dorsal").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            let (c, d) = await Red.pedir("https://onesecond.es" + web + "api/public/live/participante?d=" + dor)
            if c == 200 { det = Red.objeto(d) } else { error = true }
        }
    }
}
