import SwiftUI

/// Pantalla de inicio: una banda por prueba (oro, acero y cobre). La vinculada lleva luz verde; si emite, roja y late.
struct SelectorView: View {
    @EnvironmentObject var central: Central
    @Binding var abierta: Prueba?

    var body: some View {
        NavigationView {
            ZStack {
                Color.fondo.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Text("ONE SECOND").font(.system(size: 30, weight: .black)).tracking(3).foregroundColor(.white)
                            Text(t("Elige tu prueba", "Tria la teva prova", "Choose your event")).font(.subheadline).foregroundColor(.suave)
                        }.padding(.top, 24).padding(.bottom, 8)
                        ForEach(Prueba.todas) { p in
                            NavigationLink(tag: p, selection: $abierta) {
                                PruebaView(p: p)
                            } label: {
                                Banda(p: p)
                            }
                        }
                        Text(t("One Second Navigator: próximamente en iPhone", "One Second Navigator: aviat a l'iPhone", "One Second Navigator: coming soon on iPhone"))
                            .font(.footnote).foregroundColor(.suave).padding(.top, 8)
                    }.padding(16)
                }
                Breve()
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

struct Banda: View {
    @EnvironmentObject var central: Central
    let p: Prueba
    @State private var late = false

    var body: some View {
        let vinc = central.aj(p).vinculada
        let emite = central.emitiendo(p)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.nombre).font(.system(size: 24, weight: .heavy)).foregroundColor(.white)
                Text(p.subtitulo).font(.subheadline).foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            if vinc || emite {
                HStack(spacing: 6) {
                    Circle().fill(emite ? Color.rojo : Color.verde).frame(width: 10, height: 10)
                        .opacity(emite && late ? 0.25 : 1)
                    Text(emite ? t("EMITIENDO", "EMETENT", "SENDING") : t("VINCULADA", "VINCULADA", "LINKED"))
                        .font(.caption2.weight(.bold)).foregroundColor(.white)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.black.opacity(0.35)).cornerRadius(10)
            }
            Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 18).padding(.vertical, 22)
        .background(LinearGradient(colors: [p.oscuro, p.claro, p.medio], startPoint: .leading, endPoint: .trailing))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(p.claro.opacity(0.6), lineWidth: 1))
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { late = true } }
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
                    .background(m.1 ? Color.rojo : Color.verde.opacity(0.9)).cornerRadius(12)
                    .padding(16).transition(.move(edge: .bottom))
            }
        }.animation(.easeInOut, value: central.mensajeBreve?.0)
    }
}
