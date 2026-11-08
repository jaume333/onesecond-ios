import SwiftUI

/// Ronda la Llana y Rider 1000: la misma pantalla que en Android 1.57 (ronda/MainActivity y rider/MainActivity).
/// Arriba la bandera a cuadros con el logo, el nombre en metal pulido, el lema y tu dorsal; el cartel con el
/// próximo punto y la línea de puntos; abajo el panel: emitir / parar (manteniendo pulsado), mensajes, avisos,
/// caída / accidente, organización y ajustes.
struct EstiloTelemetria {
    let nombre: String
    let logo: String
    let acento: Color          // cobre (Ronda) o acero (Rider)
    let tinte: Color, tinteB: Color
    let burbuja: Color, burbujaB: Color
    let cromado: [Color]
    let fichas: Bool
    let tx: (String) -> String
    let f: (String, [CVarArg]) -> String

    static func de(_ p: Prueba) -> EstiloTelemetria {
        if p.id == "rider" {
            return EstiloTelemetria(nombre: "Rider 1000", logo: "logo_rider_app", acento: Color(hex: 0xAAB4C2),
                tinte: Color(hex: 0x1F242C), tinteB: Color(hex: 0x3A4250), burbuja: Color(hex: 0x282E38), burbujaB: Color(hex: 0x5A6474),
                cromado: [0xFFFFFF, 0xDFE4EA, 0x8D98A8, 0xEEF1F4, 0xB7C0CC].map { Color(hex: $0) }, fichas: false,
                tx: TxRider.t, f: { k, a in String(format: TxRider.t(k), locale: Idioma.locale, arguments: a) })
        }
        return EstiloTelemetria(nombre: "Ronda la Llana", logo: "logo_ronda", acento: Color(hex: 0xD0844A),
            tinte: Color(hex: 0x2C1A10), tinteB: Color(hex: 0x4A2A16), burbuja: Color(hex: 0x3C2414), burbujaB: Color(hex: 0x784626),
            cromado: [0xFFF3E8, 0xF0C9A6, 0xB8693A, 0xF6DCC4, 0xC98A5A].map { Color(hex: $0) }, fichas: true,
            tx: TxRonda.t, f: { k, a in String(format: TxRonda.t(k), locale: Idioma.locale, arguments: a) })
    }
}

enum TC {
    static let fondo = Color(hex: 0x0B0F15), panel = Color(hex: 0x121822), borde = Color(hex: 0x253042)
    static let texto = Color(hex: 0xE9EEF5), suave = Color(hex: 0x8D9BB0), gris = Color(hex: 0x5E6B80)
    static let azul = Color(hex: 0x4A90E2), rojo = Color(hex: 0xE05555), verde = Color(hex: 0x3FBF7F)
    static let naranja = Color(hex: 0xF0A43A), msg = Color(hex: 0x18202C)
}

struct TelemetriaView: View {
    @EnvironmentObject var central: Central
    @Environment(\.dismiss) var volver
    let p: Prueba
    @State private var hoja: Hoja? = nil
    @State private var aviso: String? = nil          // tipo de aviso elegido (panel de abajo)
    @State private var confirmarAccidente = false
    @State private var llamar = false
    @State private var fichasTotal = 0
    @State private var fichasAbiertas = 0
    @State private var cuadroMostrado = false

    enum Hoja: String, Identifiable { case vincular, chat, ajustes, fichas; var id: String { rawValue } }

    private var e: EstiloTelemetria { EstiloTelemetria.de(p) }

    var body: some View {
        let _ = central.tick
        ZStack(alignment: .top) {
            TC.fondo.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    cabecera
                    cartel.padding(.horizontal, 16).padding(.top, 12)
                    panel.padding(.top, 14)
                }
            }
            Button { volver() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundColor(TC.texto)
                    .frame(width: 40, height: 40).background(Circle().fill(Color(hex: 0x0B0F15).opacity(0.88)))
                    .overlay(Circle().stroke(TC.borde, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).padding(.top, 6)
            Breve()
        }
        .navigationBarHidden(true)
        .onAppear(perform: alAparecer)
        .sheet(item: $hoja) { h in
            Group {
                switch h {
                case .vincular: VincularView(p: p)
                case .chat: ChatView(p: p)
                case .ajustes: AjustesView(p: p, vincular: { hoja = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { hoja = .vincular } })
                case .fichas: FichasView(p: p)
                }
            }
            .environmentObject(central).environmentObject(Cuenta.shared).preferredColorScheme(.dark)
        }
        .sheet(item: Binding(get: { aviso.map { AvisoElegido(tipo: $0) } }, set: { aviso = $0?.tipo })) { a in
            PanelAviso(p: p, tipo: a.tipo, acento: e.acento) { aviso = nil }
                .environmentObject(central).preferredColorScheme(.dark)
        }
        .alert(t("¿Has tenido una caída o un accidente?", "Has tingut una caiguda o un accident?", "Have you had a crash or an accident?"), isPresented: $confirmarAccidente) {
            Button(t("Sí, enviar aviso", "Sí, enviar avís", "Yes, send alert"), role: .destructive) { enviarAviso("accidente", ""); llamar = true }
            Button(t("Cancelar", "Cancel·lar", "Cancel"), role: .cancel) {}
        } message: {
            Text(t("Se avisa a la organización con tu posición.", "S'avisa l'organització amb la teva posició.", "The organisers are alerted with your position."))
        }
        .confirmationDialog(t("¿Llamar?", "Trucar?", "Call?"), isPresented: $llamar, titleVisibility: .visible) {
            Button("📞 112") { Llamar.a("112") }
            let tel = central.aj(p).telOrg
            if !tel.isEmpty { Button("📞 " + e.tx("organizacion") + " · " + tel) { Llamar.a(tel) } }
            Button(t("Ahora no", "Ara no", "Not now"), role: .cancel) {}
        }
    }

    private func alAparecer() {
        if Demo.activo {
            fichasTotal = e.fichas ? 6 : 0; fichasAbiertas = 2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                switch Demo.pantalla { case 3: hoja = .chat; case 4: hoja = .fichas; default: break }
            }
            return
        }
        Telemetria.autoEmitir(central)
        let aj = central.aj(p)
        // al entrar sin vincular, sale directamente «Vincula la app» (una vez cada vez que se entra)
        if !cuadroMostrado && central.emitiendo == nil && !aj.vinculada {
            cuadroMostrado = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { if !central.aj(p).vinculada { hoja = .vincular } }
        }
        if e.fichas, aj.vinculada {
            Task {
                if let r = await FichasDatos.resumen(p) { fichasTotal = r.0; fichasAbiertas = max(r.1, FichasDatos.abiertas(p)) }
            }
        }
    }

    // ---------- ARRIBA: bandera a cuadros con el logo, el nombre en metal pulido, el lema y el dorsal ----------
    private var cabecera: some View {
        let aj = central.aj(p)
        return ZStack(alignment: .top) {
            BanderaCuadros().frame(height: 140)
            VStack(spacing: 0) {
                Image(e.logo).resizable().scaledToFit().frame(width: 124, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: 124 * 0.22, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
                Text(e.nombre).font(.custom("TeXGyrePagella-Bold", size: 32)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundColor(.clear)
                    .overlay(LinearGradient(stops: zip(e.cromado, [0, 0.4, 0.55, 0.75, 1.0]).map { .init(color: $0, location: $1) },
                                            startPoint: .top, endPoint: .bottom)
                        .mask(Text(e.nombre).font(.custom("TeXGyrePagella-Bold", size: 32)).lineLimit(1).minimumScaleFactor(0.6)))
                    .padding(.top, 4)
                Text("«" + e.tx("lema") + "»").font(.system(size: 13.5).italic()).foregroundColor(Color(hex: 0xC9D3DF))
                if aj.vinculada && !aj.dorsal.isEmpty {
                    HStack(spacing: 8) {
                        Text(aj.dorsal).font(.custom("TeXGyrePagella-Bold", size: 20)).foregroundColor(e.acento)
                        Text(aj.nombrePiloto).font(.system(size: 14, weight: .medium)).foregroundColor(TC.texto)
                    }.padding(.top, 6)
                }
            }
            .padding(.horizontal, 16).padding(.top, 18)
        }
    }

    // ---------- el cartel: el próximo punto, la llegada prevista y la línea de puntos ----------
    private var cartel: some View {
        let aj = central.aj(p)
        let on = central.emitiendo(p)
        let pt = central.puntos(p)
        let tp = pt.total, hechos = pt.hechos
        let sigIdx = pt.lista.firstIndex { !pt.pasados.contains($0.id) }
        var arriba = "", grande = "", derecha = "", pie = false, eta = "—", etaGrande = false
        if !aj.vinculada {
            arriba = e.tx("sin_vincular"); grande = e.nombre
        } else if tp == 0 {
            arriba = e.tx("recorrido"); grande = e.nombre
        } else if !pt.salida && hechos == 0 {
            arriba = e.tx("salida_cerrada"); grande = e.tx("salida_espera")
        } else if sigIdx == nil {
            arriba = e.f("todos_puntos", [tp, tp]); grande = e.tx("completado"); derecha = "✓"
        } else if let i = sigIdx {
            let s = pt.lista[i]
            arriba = e.f("prox_punto", [i + 1, tp])
            grande = s.n.isEmpty ? e.f("punto_n", [i + 1]) : s.n
            var dist = pt.distSig
            let reciente = central.ultimaPos.map { Date().timeIntervalSince($0) < 30 * 60 } ?? false
            if dist < 0, reciente, let l = central.ultimaLocalizacion {
                dist = l.distance(from: .init(latitude: s.lat, longitude: s.lon))
            }
            if dist >= 0 && (reciente || Demo.activo) { derecha = Self.distancia(dist) }
            if on, let l = pt.llegada { eta = Self.hora(l); etaGrande = true } else if on { eta = e.tx("calculando") }
            pie = true
        }
        let ok = pt.lista.map { pt.pasados.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            Text(arriba.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.7).foregroundColor(e.acento)
            HStack(alignment: .lastTextBaseline) {
                Text(grande).font(.custom("TeXGyrePagella-Bold", size: 25)).foregroundColor(TC.texto).lineLimit(1)
                Spacer(minLength: 8)
                if !derecha.isEmpty { Text(derecha).font(.custom("TeXGyrePagella-Bold", size: 34)).foregroundColor(e.acento) }
            }.padding(.top, 6)
            if pie {
                HStack {
                    Text(e.tx("llegada")).font(.system(size: 13.5, weight: .medium)).foregroundColor(TC.suave)
                    Spacer()
                    Text(eta).font(.system(size: etaGrande ? 19 : 14, weight: .bold)).foregroundColor(TC.fondo)
                        .padding(.horizontal, 9).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(e.acento))
                }.padding(.top, 6)
            }
            if aj.vinculada && tp > 0 {
                LineaPuntos(ok: ok, sig: sigIdx ?? -1, on: on, acento: e.acento).frame(height: 46).padding(.top, 12)
                HStack {
                    Text(pt.ultimoNombre.isEmpty ? "" : e.tx("puntos_ultimo") + " " + pt.ultimoNombre + " " + Self.hora(Date(timeIntervalSince1970: Double(pt.ultimoT) / 1000)))
                        .font(.system(size: 12.5, weight: .medium)).foregroundColor(TC.suave).lineLimit(1)
                    Spacer()
                    Text(e.f("puntos_n", [hechos, tp])).font(.system(size: 12.5, weight: .bold)).foregroundColor(TC.texto)
                }.padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [e.tinte, Color(hex: 0x151B25), TC.panel], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(e.tinteB, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    // ---------- ABAJO: el panel ----------
    private var panel: some View {
        let aj = central.aj(p)
        let on = central.emitiendo(p)
        return VStack(spacing: 0) {
            Capsule().fill(Color(hex: 0x3A414A)).frame(width: 40, height: 5).padding(.bottom, 12)
            if !on && !aj.vinculada {
                VStack(spacing: 2) {
                    Button { hoja = .vincular } label: {
                        Text("🔗  " + e.tx("vincular_ins")).font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: 0x7FB2F0))
                            .frame(minHeight: 44).padding(.horizontal, 16)
                    }
                    Text(e.tx("vincular_sub")).font(.system(size: 12.5, weight: .medium)).foregroundColor(TC.suave).multilineTextAlignment(.center)
                }.padding(.top, 4).padding(.bottom, 14)
            }
            if on && Telemetria.autoHoy(p) {
                Text("📡  " + t("Hoy es el día: emitiendo solo", "Avui és el dia: emetent sol", "It's event day: sharing automatically") + "\n"
                     + t("Al abrir la app ha empezado a enviar tu posición a la organización. No tienes que pulsar nada.",
                         "En obrir l'app ha començat a enviar la teva posició a l'organització. No has de prémer res.",
                         "The app started sharing your position with the organisers when you opened it. No need to tap anything."))
                    .font(.system(size: 12.5, weight: .medium)).foregroundColor(Color(hex: 0xC9D3DF))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0F2A1B)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x1F5A3A), lineWidth: 1))
                    .padding(.bottom, 14)
            }
            if on { bloqueOn } else { bloqueOff }
            if e.fichas && fichasTotal > 0 && aj.vinculada { botonFichas.padding(.top, 14) }
            let extra = lineasExtra()
            if !extra.isEmpty {
                Text(extra.joined(separator: "\n")).font(.system(size: 13, weight: .medium)).foregroundColor(TC.naranja)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
            if aj.vinculada { mensajes.padding(.top, 14) }
            Text(e.tx("avisar")).font(.system(size: 13.5, weight: .medium)).foregroundColor(TC.suave)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
            let tipos = ["pinchazo", "averia", "gasolina", "perdido", "abandono", "otro"]
            ForEach(0..<2) { fi in
                HStack(spacing: 8) {
                    ForEach(0..<3) { k in
                        let tipo = tipos[fi * 3 + k]
                        Button { aviso = tipo } label: {
                            VStack(spacing: 2) {
                                Text(Avisos.icono(tipo)).font(.system(size: 18))
                                Text(Self.nombreCorto(tipo)).font(.system(size: 13, weight: .bold)).foregroundColor(TC.texto).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).frame(height: 62)
                            .background(RoundedRectangle(cornerRadius: 8).fill(TC.panel))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(TC.borde, lineWidth: 1.5))
                        }
                    }
                }.padding(.top, fi == 0 ? 2 : 8)
            }
            HStack(spacing: 10) {
                Button { confirmarAccidente = true } label: {
                    Text("⚠  " + e.tx("av_accidente")).font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 56).background(RoundedRectangle(cornerRadius: 8).fill(TC.rojo))
                }.layoutPriority(1.4)
                if !aj.telOrg.isEmpty {
                    Button { Llamar.a(aj.telOrg) } label: {
                        Text("📞  " + e.tx("organizacion")).font(.system(size: 16, weight: .bold)).foregroundColor(TC.texto)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(RoundedRectangle(cornerRadius: 8).fill(TC.fondo))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(TC.gris, lineWidth: 1.5))
                    }
                }
            }.padding(.top, 16)
            misAvisos.padding(.top, 8)
            Button { hoja = .ajustes } label: {
                Text("⚙  " + e.tx("ajustes")).font(.system(size: 15, weight: .bold)).foregroundColor(TC.texto)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 8).fill(TC.fondo))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(TC.borde, lineWidth: 1.5))
            }.padding(.top, 14)
            Text(e.tx("ayuda")).font(.system(size: 13, weight: .medium)).foregroundColor(TC.suave).multilineTextAlignment(.center).padding(.top, 14)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 20)
        .background(RoundedCornerShape(radio: 20).fill(TC.fondo))
        .overlay(RoundedCornerShape(radio: 20).stroke(Color(hex: 0x2A3037), lineWidth: 1))
    }

    private var bloqueOn: some View {
        let hace = central.ultimaPos.map { Int(Date().timeIntervalSince($0)) } ?? -1
        let g = central.gpsActual(p)
        let bien = hace >= 0 && hace <= g + 5
        let sub = hace < 0 ? e.tx("esperando_gps")
            : hace < 120 ? e.f("hace_s", [hace, Int(central.ultimaPrec.rounded())]) : e.f("hace_min", [hace / 60, Int(central.ultimaPrec.rounded())])
        return HStack(spacing: 12) {
            Circle().fill(bien ? TC.verde : TC.naranja).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.tx("emitiendo")).font(.system(size: 16, weight: .bold)).foregroundColor(TC.texto)
                Text(sub).font(.system(size: 12.5, weight: .medium)).foregroundColor(TC.suave)
            }
            Spacer(minLength: 6)
            BotonMantener(arriba: "■  " + e.tx("parar_b"), abajo: e.tx("mantener")) {
                Telemetria.marcarParado(p)
                central.parar()
            } antes: {
                central.breve(e.tx("mantener_aviso"), error: true)
            }
        }
    }

    private var bloqueOff: some View {
        let aj = central.aj(p)
        let otra = central.emitiendo != nil
        let esperar = aj.vinculada && Telemetria.esDeTelemetria(p) && !Telemetria.diaDeEmitir(p)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(TC.rojo).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.tx("parado_t")).font(.system(size: 16, weight: .bold)).foregroundColor(TC.texto)
                    Text(esperar ? Telemetria.soloElDia(p) : e.tx("parado_desc")).font(.system(size: 12.5, weight: .medium)).foregroundColor(TC.suave)
                }
                Spacer()
            }
            if otra {
                Text(t("Se está emitiendo en otra prueba. Páralo allí antes.", "S'està emetent en una altra prova. Atura-ho allà abans.", "Another event is sending. Stop it there first."))
                    .font(.system(size: 13, weight: .medium)).foregroundColor(TC.naranja).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
            Button {
                if !aj.vinculada { hoja = .vincular } else { central.emitir(p) }
            } label: {
                Text("▶  " + e.tx("emitir_b")).font(.system(size: 21, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 62).background(RoundedRectangle(cornerRadius: 8).fill(TC.azul))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            }
            .disabled(otra).opacity(otra ? 0.4 : 1).padding(.top, 12)
            if central.autorizacion == .denied {
                Text(t("Sin permiso de ubicación: actívalo en Ajustes › One Second › Ubicación.", "Sense permís d'ubicació: activa'l a Configuració › One Second › Ubicació.", "No location permission: enable it in Settings › One Second › Location."))
                    .font(.system(size: 13, weight: .medium)).foregroundColor(TC.rojo).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
        }
    }

    private var botonFichas: some View {
        Button { hoja = .fichas } label: {
            HStack(spacing: 12) {
                Text("📜").font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.tx("fi_boton")).font(.custom("TeXGyrePagella-Bold", size: 19)).foregroundColor(.white)
                    Text(e.f("fi_boton_sub", [fichasAbiertas])).font(.system(size: 12.5, weight: .medium)).foregroundColor(.white.opacity(0.88))
                }
                Spacer()
                Text("›").font(.system(size: 26)).foregroundColor(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Color(hex: 0x3D1E0E), Color(hex: 0xB8693A), Color(hex: 0x6E3519)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
    }

    private func lineasExtra() -> [String] {
        guard central.emitiendo(p) else { return [] }
        var l: [String] = []
        let g = central.gpsActual(p)
        if central.ultimaPos != nil && g >= 60 { l.append(e.f("modo_seg", [g / 60])) }
        if central.pendientes > 3 { l.append(e.f("pendientes", [central.pendientes])) }
        if central.codigoMal { l.append(e.tx("error_codigo")) } else if central.sinRed { l.append(e.tx("sin_red")) }
        if central.falso { l.append(e.tx("falso")) }
        return l
    }

    private var mensajes: some View {
        MensajesCaja(p: p, tx: e.tx, acento: e.acento, boton: e.acento, botonTexto: TC.fondo, burbuja: e.burbuja, burbujaB: e.burbujaB) { hoja = .chat }
    }

    private var misAvisos: some View { MisAvisos(p: p) }

    private func enviarAviso(_ tipo: String, _ texto: String) {
        var pos: (Double, Double, Double)? = nil
        if let l = central.ultimaLocalizacion { pos = (l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy) }
        central.avisos(p).nuevo(tipo: tipo, texto: texto, pos: pos)
        central.rafaga()
        central.breve(t("Aviso guardado: se envía en cuanto haya cobertura.", "Avís desat: s'envia quan hi hagi cobertura.", "Alert saved: sent as soon as there is coverage."))
        Task { await central.avisos(p).sincronizar(); central.tick += 1 }
    }

    static func nombreCorto(_ tipo: String) -> String {
        let n = tipo == "otro" ? t("Otro", "Altre", "Other") : Avisos.nombre(tipo)
        if let r = n.range(of: " / ") { return String(n[..<r.lowerBound]) }
        return n
    }
    static func hora(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    static func distancia(_ m: Double) -> String {
        if m < 1000 { return "\(Int((m / 10).rounded()) * 10) m" }
        if m < 10000 { return String(format: "%.1f km", locale: Idioma.locale, m / 1000) }
        return "\(Int((m / 1000).rounded())) km"
    }
}

private struct AvisoElegido: Identifiable { let tipo: String; var id: String { tipo } }

/// El panel que sube desde abajo: el aviso elegido, un texto opcional y «Enviar aviso».
struct PanelAviso: View {
    @EnvironmentObject var central: Central
    let p: Prueba
    let tipo: String
    let acento: Color
    let cerrar: () -> Void
    @State private var nota = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Avisos.icono(tipo) + "  " + (tipo == "otro" ? t("Otro", "Altre", "Other") : Avisos.nombre(tipo))).font(.title3.bold()).foregroundColor(TC.texto)
                Spacer()
                Button(t("Cancelar", "Cancel·lar", "Cancel")) { cerrar() }.foregroundColor(TC.suave)
            }
            TextField(t("Explica qué pasa (opcional)", "Explica què passa (opcional)", "Explain what's happening (optional)"), text: $nota)
                .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(TC.msg)).foregroundColor(TC.texto)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TC.borde, lineWidth: 1.5))
            Button {
                var pos: (Double, Double, Double)? = nil
                if let l = central.ultimaLocalizacion { pos = (l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy) }
                central.avisos(p).nuevo(tipo: tipo, texto: nota.trimmingCharacters(in: .whitespacesAndNewlines), pos: pos)
                central.rafaga()
                central.breve(t("Aviso guardado: se envía en cuanto haya cobertura.", "Avís desat: s'envia quan hi hagi cobertura.", "Alert saved: sent as soon as there is coverage."))
                Task { await central.avisos(p).sincronizar(); central.tick += 1 }
                cerrar()
            } label: {
                Text(t("ENVIAR AVISO", "ENVIAR AVÍS", "SEND ALERT")).font(.system(size: 17, weight: .bold)).foregroundColor(TC.fondo)
                    .frame(maxWidth: .infinity).frame(height: 54).background(RoundedRectangle(cornerRadius: 8).fill(acento))
            }
            Spacer()
        }
        .padding(20).background(TC.fondo.ignoresSafeArea())
    }
}

/// Bandera a cuadros que se funde con el fondo (la de One Second Rally).
struct BanderaCuadros: View {
    var body: some View {
        Canvas { c, s in
            let lado: CGFloat = 15
            c.fill(Path(CGRect(origin: .zero, size: s)), with: .color(TC.fondo))
            var fila = 0
            while CGFloat(fila) * lado < s.height {
                var col = 0
                while CGFloat(col) * lado < s.width {
                    if (fila + col) % 2 == 0 { c.fill(Path(CGRect(x: CGFloat(col) * lado, y: CGFloat(fila) * lado, width: lado, height: lado)), with: .color(Color(hex: 0x1E2634))) }
                    col += 1
                }
                fila += 1
            }
            c.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(
                Gradient(stops: [.init(color: TC.fondo.opacity(0), location: 0), .init(color: TC.fondo.opacity(0.35), location: 0.45), .init(color: TC.fondo, location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
        }
    }
}

/// Línea horizontal con los puntos de control: los pasados con ✓, el próximo con un halo, los que faltan en gris.
struct LineaPuntos: View {
    let ok: [Bool]
    let sig: Int
    let on: Bool
    let acento: Color
    var body: some View {
        Canvas { c, s in
            let n = ok.count
            guard n > 0 else { return }
            let grande = n <= 12
            let r: CGFloat = grande ? 12 : 7, borde: CGFloat = grande ? 3 : 2
            let x0 = r + 4, x1 = s.width - r - 4, y = r + 4
            let paso = n > 1 ? (x1 - x0) / CGFloat(n - 1) : 0
            let ac = on ? acento : Color(hex: 0x969EA8)
            c.fill(Path(roundedRect: CGRect(x: x0, y: y - 2, width: x1 - x0, height: 4), cornerRadius: 2), with: .color(Color(hex: 0x253042)))
            let ultimo = ok.lastIndex(of: true) ?? -1
            if ultimo > 0 { c.fill(Path(roundedRect: CGRect(x: x0, y: y - 2, width: paso * CGFloat(ultimo), height: 4), cornerRadius: 2), with: .color(ac)) }
            for i in 0..<n {
                let x = n > 1 ? x0 + paso * CGFloat(i) : (x0 + x1) / 2
                let hecho = ok[i], prox = i == sig
                if prox { c.fill(Path(ellipseIn: CGRect(x: x - r - 5, y: y - r - 5, width: 2 * (r + 5), height: 2 * (r + 5))), with: .color(ac.opacity(0.24))) }
                let circ = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                c.fill(circ, with: .color(hecho ? ac : prox ? TC.fondo : TC.panel))
                let aro = Path(ellipseIn: CGRect(x: x - r + borde / 2, y: y - r + borde / 2, width: 2 * r - borde, height: 2 * r - borde))
                c.stroke(aro, with: .color(hecho || prox ? ac : Color(hex: 0x3A4558)), lineWidth: borde)
                if grande {
                    let num: String = hecho ? "✓" : "\(i + 1)"
                    let col: Color = hecho ? (on ? Color(hex: 0x1A1203) : TC.fondo) : (prox ? Color.white : TC.suave)
                    c.draw(Text(num).font(.system(size: 11, weight: .bold)).foregroundColor(col), at: CGPoint(x: x, y: y))
                }
                if grande || prox || i == 0 || i == n - 1 {
                    let col: Color = prox ? Color.white : TC.suave
                    c.draw(Text("P\(i + 1)").font(.system(size: 10, weight: .bold)).foregroundColor(col), at: CGPoint(x: x, y: y + r + 9))
                }
            }
        }
    }
}

/// Botón PARAR: hay que mantenerlo pulsado 2 s (se llena de rojo); así no se para por un toque sin querer.
struct BotonMantener: View {
    let arriba: String
    let abajo: String
    let alAcabar: () -> Void
    let antes: () -> Void
    var dura: Double = 2
    @State private var hecho: CGFloat = 0
    @State private var desde = Date.distantPast

    var body: some View {
        VStack(spacing: 0) {
            Text(arriba).font(.system(size: 15, weight: .bold)).foregroundColor(TC.texto)
            Text(abajo).font(.system(size: 11, weight: .medium)).foregroundColor(TC.suave)
        }
        .padding(.horizontal, 16).frame(height: 48)
        .background(GeometryReader { g in
            RoundedRectangle(cornerRadius: 8).fill(Color(red: 227 / 255, green: 19 / 255, blue: 47 / 255).opacity(0.59))
                .frame(width: g.size.width * hecho)
        })
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(hecho > 0 ? TC.rojo : TC.gris, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: dura, maximumDistance: 40, pressing: { p in
            if p {
                desde = Date()
                hecho = 0
                withAnimation(.linear(duration: dura)) { hecho = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.15)) { hecho = 0 }
                if Date().timeIntervalSince(desde) < dura - 0.05 { antes() }
            }
        }, perform: {
            hecho = 0
            alAcabar()
        })
    }
}

/// Burbuja de chat: la organización a la izquierda (pico abajo a la izquierda), el piloto a la derecha.
struct Burbuja: Shape {
    let yo: Bool
    func path(in r: CGRect) -> Path {
        let g: CGFloat = 16, p: CGFloat = 4
        return Path { a in
            let tl = g, tr = g, br = yo ? p : g, bl = yo ? g : p
            a.move(to: CGPoint(x: r.minX + tl, y: r.minY))
            a.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
            a.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr)
            a.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
            a.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br)
            a.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
            a.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl)
            a.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
            a.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl)
        }
    }
}

/// Los últimos mensajes de la conversación con la organización y el botón para abrir el chat entero.
struct MensajesCaja: View {
    @EnvironmentObject var central: Central
    let p: Prueba
    let tx: (String) -> String
    let acento: Color, boton: Color, botonTexto: Color, burbuja: Color, burbujaB: Color
    let abrir: () -> Void

    var body: some View {
        let m = central.mensajes(p)
        let conv = m.lineas
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("✉  " + tx("chat_org")).font(.system(size: 15, weight: .bold)).foregroundColor(TC.texto)
                Spacer()
                if m.sinLeer > 0 {
                    Text("\(m.sinLeer)").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 1).background(Capsule().fill(TC.rojo))
                }
            }
            if conv.isEmpty {
                Text(tx("chat_vacio")).font(.system(size: 13.5, weight: .medium)).foregroundColor(TC.suave)
            } else {
                ForEach(conv.suffix(4)) { x in fila(x) }
            }
            Button(action: abrir) {
                Text("✎  " + tx(conv.isEmpty ? "chat_escribir" : "chat_abrir")).font(.system(size: 15, weight: .bold)).foregroundColor(botonTexto)
                    .frame(maxWidth: .infinity).frame(height: 46).background(RoundedRectangle(cornerRadius: 8).fill(boton))
            }.padding(.top, 4)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(TC.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(TC.borde, lineWidth: 1.5))
        .contentShape(Rectangle()).onTapGesture(perform: abrir)
    }

    private func pie(_ x: Mensajes.Linea) -> String {
        let h = TelemetriaView.hora(Date(timeIntervalSince1970: Double(x.t) / 1000))
        if !x.yo { return h }
        return h + "  ·  " + (x.enviada ? "✓ " + tx("resp_enviada") : "⏳ " + tx("resp_enviando"))
    }
    private func colorPie(_ x: Mensajes.Linea) -> Color { x.yo ? (x.enviada ? TC.verde : TC.naranja) : TC.suave }

    private func fila(_ x: Mensajes.Linea) -> some View {
        HStack {
            if x.yo { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 2) {
                if !x.yo {
                    Text(tx("organizacion") + (x.todos ? " · " + tx("chat_todos") : "")).font(.system(size: 11, weight: .bold)).foregroundColor(acento)
                }
                Text(x.texto).font(.system(size: 15.5, weight: .medium)).foregroundColor(TC.texto)
                Text(pie(x))
                    .font(.system(size: 11, weight: .medium)).foregroundColor(colorPie(x))
                    .frame(maxWidth: x.yo ? .infinity : nil, alignment: .trailing)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 7)
            .background(Burbuja(yo: x.yo).fill(x.yo ? burbuja : TC.msg))
            .overlay(Burbuja(yo: x.yo).stroke(x.yo ? burbujaB : TC.borde, style: StrokeStyle(lineWidth: 1, dash: !x.yo && x.todos ? [5, 4] : [])))
            if !x.yo { Spacer(minLength: 50) }
        }
    }
}

/// Mis avisos: cada aviso con su estado y la respuesta de la organización.
struct MisAvisos: View {
    @EnvironmentObject var central: Central
    let p: Prueba
    var body: some View {
        let av = central.avisos(p)
        VStack(spacing: 8) {
            ForEach(Array(av.lista.reversed().enumerated()), id: \.offset) { _, o in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Avisos.icono(o.str("tipo")) + "  " + Avisos.nombre(o.str("tipo"))).font(.system(size: 15, weight: .bold)).foregroundColor(TC.texto)
                        Spacer()
                        Text(TelemetriaView.hora(Date(timeIntervalSince1970: Double(o.int("time")) / 1000))).font(.system(size: 12)).foregroundColor(TC.suave)
                    }
                    if !o.str("texto").isEmpty { Text(o.str("texto")).font(.system(size: 13)).foregroundColor(TC.suave) }
                    Text(o.bool("borrar") ? t("Cancelando…", "Cancel·lant…", "Cancelling…") : Avisos.estadoTexto(o.bool("enviado") ? o.str("estado") : ""))
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(o.bool("enviado") ? TC.verde : TC.naranja)
                    if !o.str("respuesta").isEmpty {
                        Text("💬 " + o.str("respuesta")).font(.system(size: 14)).foregroundColor(TC.texto)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(TC.verde.opacity(0.18)))
                    }
                    if !Avisos.cerrado(o) && !o.bool("borrar") {
                        Button(t("Quitar el aviso", "Treure l'avís", "Remove alert"), role: .destructive) { av.quitar(o.str("id")); central.tick += 1 }
                            .font(.system(size: 13))
                    }
                }
                .padding(12).padding(.leading, 4).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(TC.panel))
                .overlay(HStack { Rectangle().fill(o.bool("enviado") ? TC.verde : TC.naranja).frame(width: 4); Spacer() }.clipShape(RoundedRectangle(cornerRadius: 10)))
            }
        }
    }
}
