import SwiftUI

/// Mensajes con la organización.
struct ChatView: View {
    @EnvironmentObject var central: Central
    @Environment(\.dismiss) var cerrar
    let p: Prueba
    @State private var texto = ""

    var body: some View {
        let _ = central.tick
        let m = central.mensajes(p)
        NavigationView {
            VStack(spacing: 0) {
                ScrollViewReader { sv in
                    ScrollView {
                        VStack(spacing: 8) {
                            if m.lineas.isEmpty {
                                Text(t("Aún no hay mensajes de la organización.", "Encara no hi ha missatges de l'organització.", "No messages from the organisers yet."))
                                    .foregroundColor(.suave).padding(.top, 40)
                            }
                            ForEach(m.lineas) { l in
                                HStack {
                                    if l.yo { Spacer(minLength: 40) }
                                    VStack(alignment: l.yo ? .trailing : .leading, spacing: 3) {
                                        if l.todos { Text(t("A todos", "A tothom", "To everyone")).font(.caption2.bold()).foregroundColor(.oro) }
                                        Text(l.texto).foregroundColor(.white)
                                        Text(Date(timeIntervalSince1970: Double(l.t) / 1000).formatted(date: .omitted, time: .shortened)
                                             + (l.yo ? (l.enviada ? " ✓" : " ⏳") : ""))
                                            .font(.caption2).foregroundColor(.suave)
                                    }
                                    .padding(10).background(l.yo ? Color.verde.opacity(0.25) : Color.panel).cornerRadius(12)
                                    if !l.yo { Spacer(minLength: 40) }
                                }.id(l.id)
                            }
                        }.padding(12)
                    }
                    .onAppear { if let u = m.lineas.last { sv.scrollTo(u.id, anchor: .bottom) } }
                }
                HStack(spacing: 8) {
                    TextField(t("Escribe a la organización…", "Escriu a l'organització…", "Write to the organisers…"), text: $texto)
                        .padding(10).background(Color.panel).cornerRadius(10).foregroundColor(.white)
                    Button {
                        m.responder(texto); texto = ""; central.tick += 1
                        Task { await m.enviarRespuestas(); central.tick += 1 }
                    } label: { Image(systemName: "paperplane.fill").font(.title3) }
                        .disabled(texto.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding(10).background(Color.fondo)
            }
            .background(Color.fondo.ignoresSafeArea())
            .navigationTitle(t("Mensajes", "Missatges", "Messages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("Cerrar", "Tancar", "Close")) { cerrar() } } }
            .task { if Demo.activo { return }; await m.consultar(); await m.marcarLeidos(); central.tick += 1 }
        }
    }
}
