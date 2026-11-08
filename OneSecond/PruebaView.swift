import SwiftUI

/// Pantalla de una prueba: vincular, EMITIR / PARAR, estado del GPS, puntos de control, avisos y mensajes.
struct PruebaView: View {
    @EnvironmentObject var central: Central
    let p: Prueba
    @State private var hoja: Hoja? = nil

    enum Hoja: String, Identifiable { case vincular, avisos, chat, ajustes; var id: String { rawValue } }

    var body: some View {
        let _ = central.tick
        let aj = central.aj(p)
        ZStack {
            Color.fondo.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    cabecera
                    if !aj.vinculada {
                        sinVincular
                    } else {
                        emision
                        if p.conPuntos { puntosCard }
                        botones
                    }
                }.padding(16)
            }
            Breve()
        }
        .navigationTitle(p.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { hoja = .ajustes } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(item: $hoja) { h in
            Group {
                switch h {
                case .vincular: VincularView(p: p)
                case .avisos: AvisosView(p: p)
                case .chat: ChatView(p: p)
                case .ajustes: AjustesView(p: p, vincular: { hoja = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { hoja = .vincular } })
                }
            }
            .environmentObject(central)
            .preferredColorScheme(.dark)
        }
    }

    private var cabecera: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.nombre).font(.title2.weight(.heavy)).foregroundColor(.white)
                Text(p.subtitulo).font(.subheadline).foregroundColor(.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(18)
        .background(LinearGradient(colors: [p.oscuro, p.claro, p.medio], startPoint: .leading, endPoint: .trailing))
        .cornerRadius(16)
    }

    private var sinVincular: some View {
        VStack(spacing: 14) {
            Text(t("Esta prueba no está vinculada", "Aquesta prova no està vinculada", "This event is not linked"))
                .font(.headline).foregroundColor(.white)
            Text(t("Vincula la app con tu inscripción: escanea el QR que te da la organización, pega tu dirección de piloto o, en las pruebas que lo permiten, usa tu dorsal y tu teléfono.",
                   "Vincula l'app amb la teva inscripció: escaneja el QR que et dona l'organització, enganxa la teva adreça de pilot o, a les proves que ho permeten, fes servir el dorsal i el telèfon.",
                   "Link the app to your entry: scan the QR from the organisers, paste your rider address or, where available, use your number and phone."))
                .font(.subheadline).foregroundColor(.suave).multilineTextAlignment(.center)
            BotonGrande(texto: "🔗  " + t("VINCULAR", "VINCULAR", "LINK"), color: .oro, textoColor: .black) { hoja = .vincular }
        }
        .padding(18).background(Color.panel).cornerRadius(16)
    }

    private var emision: some View {
        let emite = central.emitiendo(p)
        let otra = central.emitiendo != nil && !emite
        return VStack(spacing: 12) {
            HStack {
                Text("● " + (emite ? (central.ultimaPos == nil ? t("BUSCANDO GPS", "BUSCANT GPS", "FINDING GPS") : t("EMITIENDO", "EMETENT", "SENDING")) : t("PARADO", "ATURAT", "STOPPED")))
                    .font(.caption.weight(.bold)).tracking(1.5).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(emite ? (central.ultimaPos == nil ? Color.naranja : Color.rojo) : Color.gray.opacity(0.5)).cornerRadius(8)
                Spacer()
            }
            if emite {
                VStack(alignment: .leading, spacing: 6) {
                    fila(t("Posiciones enviadas", "Posicions enviades", "Positions sent"), "\(central.enviadas)")
                    fila(t("Pendientes de enviar", "Pendents d'enviar", "Waiting to send"), "\(central.pendientes)")
                    if let u = central.ultimaPos {
                        fila(t("Última posición", "Última posició", "Last position"), "\(Int(Date().timeIntervalSince(u))) s · ±\(Int(central.ultimaPrec)) m")
                    }
                    if central.sinRed { aviso(t("Sin cobertura: se guardan y se envían después.", "Sense cobertura: es guarden i s'envien després.", "No coverage: saved and sent later."), .naranja) }
                    if central.codigoMal { aviso(t("El servidor no reconoce tu código. Vuelve a vincular.", "El servidor no reconeix el teu codi. Torna a vincular.", "The server does not recognise your code. Link again."), .rojo) }
                    if central.falso { aviso(t("Ubicación simulada: no cuenta.", "Ubicació simulada: no compta.", "Simulated location: does not count."), .rojo) }
                }
                Text(t("Puedes apagar la pantalla: sigue emitiendo hasta que pulses PARAR. No cierres la app desde la multitarea.",
                       "Pots apagar la pantalla: continua emetent fins que premis ATURAR. No tanquis l'app des de la multitasca.",
                       "You can turn the screen off: it keeps sending until you press STOP. Do not close the app from the app switcher."))
                    .font(.footnote).foregroundColor(.suave)
                BotonGrande(texto: "■  " + t("PARAR", "ATURAR", "STOP"), color: .rojo, textoColor: .white) { central.parar() }
            } else {
                if otra {
                    aviso(t("Se está emitiendo en otra prueba. Páralo allí antes.", "S'està emetent en una altra prova. Atura-ho allà abans.", "Another event is sending. Stop it there first."), .naranja)
                }
                BotonGrande(texto: "▶  " + t("EMITIR", "EMETRE", "SEND"), color: .verde, textoColor: .black) { central.emitir(p) }
                    .disabled(otra).opacity(otra ? 0.4 : 1)
                if central.autorizacion == .denied {
                    aviso(t("Sin permiso de ubicación: actívalo en Ajustes › One Second › Ubicación › Mientras se usa la app.", "Sense permís d'ubicació: activa'l a Configuració › One Second › Ubicació.", "No location permission: enable it in Settings › One Second › Location."), .rojo)
                }
            }
        }
        .padding(18).background(Color.panel).cornerRadius(16)
    }

    private var puntosCard: some View {
        let pt = central.puntos(p)
        return VStack(alignment: .leading, spacing: 6) {
            Text(t("PUNTOS DE CONTROL", "PUNTS DE CONTROL", "CHECKPOINTS")).font(.caption.weight(.bold)).tracking(1.5).foregroundColor(.suave)
            if pt.total == 0 {
                Text(t("Se descargan al emitir.", "Es descarreguen en emetre.", "Downloaded when sending.")).foregroundColor(.suave)
            } else {
                fila(t("Pasados", "Passats", "Passed"), "\(pt.hechos) / \(pt.total)")
                if let s = pt.siguiente {
                    fila(t("Próximo", "Següent", "Next"), s.n.isEmpty ? "#\(s.id)" : s.n)
                    if pt.distSig >= 0 { fila(t("Distancia en línea recta", "Distància en línia recta", "Straight-line distance"), pt.distSig >= 1000 ? String(format: "%.1f km", pt.distSig / 1000) : "\(Int(pt.distSig)) m") }
                    if let l = pt.llegada { fila(t("Llegada prevista", "Arribada prevista", "Expected arrival"), l.formatted(date: .omitted, time: .shortened)) }
                } else {
                    Text(t("¡Todos los puntos pasados!", "Tots els punts passats!", "All checkpoints passed!")).foregroundColor(.verde).bold()
                }
                if !pt.salida { aviso(t("La organización aún no te ha dado la salida.", "L'organització encara no t'ha donat la sortida.", "The organisers have not started you yet."), .naranja) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).background(Color.panel).cornerRadius(16)
    }

    private var botones: some View {
        let sinLeer = central.mensajes(p).sinLeer
        return HStack(spacing: 12) {
            BotonGrande(texto: "⚠️  " + t("AVISOS", "AVISOS", "ALERTS"), color: .naranja, textoColor: .black) { hoja = .avisos }
            BotonGrande(texto: "💬  " + t("MENSAJES", "MISSATGES", "MESSAGES") + (sinLeer > 0 ? " (\(sinLeer))" : ""), color: .panel, textoColor: .white) { hoja = .chat }
        }
    }

    private func fila(_ a: String, _ b: String) -> some View {
        HStack { Text(a).foregroundColor(.suave); Spacer(); Text(b).foregroundColor(.white).bold() }.font(.subheadline)
    }
    private func aviso(_ s: String, _ c: Color) -> some View {
        Text(s).font(.footnote.weight(.semibold)).foregroundColor(c).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BotonGrande: View {
    let texto: String
    let color: Color
    let textoColor: Color
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Text(texto).font(.headline.weight(.heavy)).foregroundColor(textoColor)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(color).cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borde, lineWidth: color == .panel ? 1 : 0))
        }
    }
}

/// Ajustes de la prueba: tu vinculación, cambiarla o quitarla, y acerca de.
struct AjustesView: View {
    @EnvironmentObject var central: Central
    @Environment(\.dismiss) var cerrar
    let p: Prueba
    let vincular: () -> Void

    var body: some View {
        let aj = central.aj(p)
        NavigationView {
            List {
                Section(t("Vinculación", "Vinculació", "Link")) {
                    if aj.vinculada {
                        Text(aj.url).font(.footnote).foregroundColor(.suave).textSelection(.enabled)
                    } else {
                        Text(t("Sin vincular", "Sense vincular", "Not linked")).foregroundColor(.suave)
                    }
                    Button(aj.vinculada ? t("Cambiar la vinculación", "Canviar la vinculació", "Change link") : t("Vincular", "Vincular", "Link")) { vincular() }
                        .disabled(central.emitiendo(p))
                    if aj.vinculada {
                        Button(t("Desvincular", "Desvincular", "Unlink"), role: .destructive) { central.desvincular(p); cerrar() }
                            .disabled(central.emitiendo(p))
                    }
                }
                if !aj.telOrg.isEmpty {
                    Section(t("Organización", "Organització", "Organisers")) {
                        Button("📞  " + aj.telOrg) { Llamar.a(aj.telOrg) }
                    }
                }
                Section(t("Acerca de", "Quant a", "About")) {
                    Text("One Second · " + p.nombre)
                    Text(t("Versión ", "Versió ", "Version ") + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                        .foregroundColor(.suave)
                    Link(t("Política de privacidad", "Política de privacitat", "Privacy policy"), destination: URL(string: "https://onesecond.es/privacidad")!)
                }
            }
            .navigationTitle(t("Ajustes", "Configuració", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("Hecho", "Fet", "Done")) { cerrar() } } }
        }
    }
}

enum Llamar {
    static func a(_ tel: String) {
        let n = tel.filter { "+0123456789".contains($0) }
        if let u = URL(string: "tel://" + n) { UIApplication.shared.open(u) }
    }
}
