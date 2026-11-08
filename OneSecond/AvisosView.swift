import SwiftUI

/// Avisos a la organización: elegir el tipo, una nota opcional y enviar. Caída / accidente aparte, con llamadas.
struct AvisosView: View {
    @EnvironmentObject var central: Central
    @Environment(\.dismiss) var cerrar
    let p: Prueba
    @State private var elegido: String? = nil
    @State private var nota = ""
    @State private var confirmarAccidente = false
    @State private var llamar = false

    var body: some View {
        let _ = central.tick
        let av = central.avisos(p)
        let tel = central.aj(p).telOrg
        NavigationView {
            ZStack {
                Color.fondo.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Button { confirmarAccidente = true } label: {
                            Text("⚠️  " + Avisos.nombre("accidente")).font(.title3.weight(.heavy)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 18).background(Color.rojo).cornerRadius(14)
                        }
                        Text(t("Otra incidencia", "Una altra incidència", "Another issue")).font(.headline).foregroundColor(.white)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Avisos.tipos, id: \.self) { tp in
                                Button { elegido = tp } label: {
                                    VStack(spacing: 4) {
                                        Text(Avisos.icono(tp)).font(.title2)
                                        Text(Avisos.nombre(tp)).font(.caption.weight(.semibold)).foregroundColor(.white).multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 74).padding(6)
                                    .background(elegido == tp ? Color.naranja.opacity(0.35) : Color.panel).cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(elegido == tp ? Color.naranja : Color.borde, lineWidth: elegido == tp ? 2 : 1))
                                }
                            }
                        }
                        if let tp = elegido {
                            TextField(t("Nota para la organización (opcional)", "Nota per a l'organització (opcional)", "Note for the organisers (optional)"), text: $nota)
                                .padding(12).background(Color.panel).cornerRadius(8).foregroundColor(.white)
                            BotonGrande(texto: t("ENVIAR AVISO", "ENVIAR AVÍS", "SEND ALERT") + ": " + Avisos.nombre(tp), color: .naranja, textoColor: .black) {
                                enviar(tp, nota); elegido = nil; nota = ""
                            }
                        }
                        if !av.lista.isEmpty {
                            Text(t("Mis avisos", "Els meus avisos", "My alerts")).font(.headline).foregroundColor(.white).padding(.top, 6)
                            ForEach(Array(av.lista.reversed().enumerated()), id: \.offset) { _, o in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(Avisos.icono(o.str("tipo")) + "  " + Avisos.nombre(o.str("tipo"))).bold().foregroundColor(.white)
                                        Spacer()
                                        Text(Date(timeIntervalSince1970: Double(o.int("time")) / 1000).formatted(date: .omitted, time: .shortened)).foregroundColor(.suave).font(.caption)
                                    }
                                    if !o.str("texto").isEmpty { Text(o.str("texto")).font(.footnote).foregroundColor(.suave) }
                                    Text(o.bool("borrar") ? t("Cancelando…", "Cancel·lant…", "Cancelling…") : Avisos.estadoTexto(o.bool("enviado") ? o.str("estado") : ""))
                                        .font(.footnote.weight(.semibold)).foregroundColor(o.bool("enviado") ? .verde : .naranja)
                                    if !o.str("respuesta").isEmpty {
                                        Text("💬 " + o.str("respuesta")).font(.callout).foregroundColor(.white).padding(8).background(Color.verde.opacity(0.2)).cornerRadius(8)
                                    }
                                    if !Avisos.cerrado(o) && !o.bool("borrar") {
                                        Button(t("Quitar el aviso", "Treure l'avís", "Remove alert"), role: .destructive) { av.quitar(o.str("id")); central.tick += 1 }
                                            .font(.footnote)
                                    }
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.panel).cornerRadius(12)
                            }
                        }
                    }.padding(16)
                }
            }
            .navigationTitle(t("Avisos", "Avisos", "Alerts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("Cerrar", "Tancar", "Close")) { cerrar() } } }
            .alert(t("¿Has tenido una caída o un accidente?", "Has tingut una caiguda o un accident?", "Have you had a crash or an accident?"), isPresented: $confirmarAccidente) {
                Button(t("Sí, enviar aviso", "Sí, enviar avís", "Yes, send alert"), role: .destructive) { enviar("accidente", ""); llamar = true }
                Button(t("Cancelar", "Cancel·lar", "Cancel"), role: .cancel) {}
            } message: {
                Text(t("Se avisa a la organización con tu posición.", "S'avisa l'organització amb la teva posició.", "The organisers are alerted with your position."))
            }
            .confirmationDialog(t("¿Llamar?", "Trucar?", "Call?"), isPresented: $llamar, titleVisibility: .visible) {
                Button("📞 112") { Llamar.a("112") }
                if !tel.isEmpty { Button("📞 " + t("Organización", "Organització", "Organisers") + " · " + tel) { Llamar.a(tel) } }
                Button(t("Ahora no", "Ara no", "Not now"), role: .cancel) {}
            }
        }
    }

    private func enviar(_ tipo: String, _ texto: String) {
        var pos: (Double, Double, Double)? = nil
        if let l = central.ultimaLocalizacion { pos = (l.coordinate.latitude, l.coordinate.longitude, l.horizontalAccuracy) }
        central.avisos(p).nuevo(tipo: tipo, texto: texto, pos: pos)
        central.rafaga()
        central.breve(t("Aviso guardado: se envía en cuanto haya cobertura.", "Avís desat: s'envia quan hi hagi cobertura.", "Alert saved: sent as soon as there is coverage."))
        Task { await central.avisos(p).sincronizar(); central.tick += 1 }
    }
}
