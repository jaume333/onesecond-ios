import SwiftUI
import UniformTypeIdentifiers

/// One Second Navigator: elegir la ruta (como Navigator.java): las de One Second por prueba (del servidor), abrir un GPX
/// del iPhone (o compartido desde WhatsApp), las guardadas en el iPhone y «Empezar a navegar».
struct NavigatorView: View {
    @ObservedObject private var nav = Navegacion.shared
    @EnvironmentObject var central: Central
    @Environment(\.dismiss) var cerrar
    @State private var servidor: [String: [Rutas.Remota]]? = nil
    @State private var cargando = true
    @State private var sinRed = false
    @AppStorage("nav_prueba") private var elegida = ""
    @State private var guardadas: [Rutas.Guardada] = Rutas.guardadas
    @State private var bajando: String? = nil
    @State private var abrir: String? = nil
    @State private var importar = false
    @State private var borrar: Rutas.Guardada? = nil
    @State private var aviso: String? = nil

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            NavigationLink(isActive: Binding(get: { abrir != nil }, set: { if !$0 { abrir = nil; guardadas = Rutas.guardadas } })) {
                Group { if let a = abrir { NavMapaView(archivo: a) } }
            } label: { EmptyView() }.hidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Button { cerrar() } label: { Text("‹").font(.system(size: 30)).foregroundColor(.suave).padding(.trailing, 10).padding(.bottom, 4) }
                            .accessibilityLabel(t("Volver", "Tornar", "Back"))
                        Image("ic_navigator").resizable().scaledToFit().frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("One Second Navigator").font(.custom("TeXGyrePagella-Bold", size: 21)).foregroundColor(.texto)
                            Texto(t("Elige la ruta que quieres seguir", "Tria la ruta que vols seguir", "Choose the route to follow"), 12.5, .suave)
                        }.padding(.leading, 12)
                    }.padding(.top, 8).padding(.bottom, 6)
                    navegandoVista.padding(.top, 4)

                    Etiqueta(t("RUTAS DE ONE SECOND", "RUTES DE ONE SECOND", "ONE SECOND ROUTES")).padding(.top, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(carpetas, id: \.self) { c in
                                let si = c == elegidaReal
                                Button { elegida = c } label: {
                                    Text(Rutas.nombrePrueba(c)).font(.system(size: 12, weight: .medium)).foregroundColor(si ? .white : Color(hex: 0xC9D3DF))
                                        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 7)
                                        .background(Capsule().fill(si ? Rutas.colorPrueba(c) : .clear))
                                        .overlay(Capsule().stroke(si ? Rutas.colorPrueba(c) : Color.borde, lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.padding(.top, 8)
                    if cargando && servidor == nil { Texto(t("Cargando las rutas…", "Carregant les rutes…", "Loading routes…"), 12.5, .suave).padding(.top, 8) }
                    if sinRed { Texto(t("Sin conexión: se ven las rutas guardadas en el móvil.", "Sense connexió: es veuen les rutes desades al mòbil.", "No connection: showing routes saved on this phone."), 12.5, .suave).padding(.top, 8) }
                    listaServidor.padding(.top, 4)

                    Etiqueta(t("OTRAS RUTAS", "ALTRES RUTES", "OTHER ROUTES")).padding(.top, 22)
                    Button { importar = true } label: {
                        Text("📂   " + t("Abrir un GPX del móvil", "Obrir un GPX del mòbil", "Open a GPX from this phone"))
                            .font(.system(size: 15.5, weight: .medium)).foregroundColor(Color(hex: 0x9CC4F5))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0F1A2B)))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x2F5AA0), lineWidth: 1))
                    }.buttonStyle(.plain).padding(.top, 8)
                    HStack(alignment: .top, spacing: 10) {
                        Text("💬").font(.system(size: 22))
                        Texto(t("¿Te han pasado una ruta por WhatsApp? Pulsa el archivo, «Compartir» y elige One Second: se abre aquí sola.",
                                "T'han passat una ruta per WhatsApp? Prem el fitxer, «Compartir» i tria One Second: s'obre aquí sola.",
                                "Got a route on WhatsApp? Tap the file, «Share» and choose One Second: it opens here by itself."), 13, Color(hex: 0xBFE9CF))
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0F2A1B)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x1F5A3A), lineWidth: 1)).padding(.top, 12)

                    Etiqueta(t("GUARDADAS EN ESTE MÓVIL", "DESADES EN AQUEST MÒBIL", "SAVED ON THIS PHONE")).padding(.top, 22)
                    if guardadas.isEmpty {
                        Texto(t("Aún no hay rutas en este móvil.", "Encara no hi ha rutes en aquest mòbil.", "No routes on this phone yet."), 13, .suave).padding(.top, 8)
                    } else {
                        ForEach(guardadas) { g in tarjeta(g, nil).padding(.top, 8) }
                        Texto(t("Mantén pulsada una ruta para borrarla del móvil.", "Mantén premuda una ruta per esborrar-la del mòbil.", "Long-press a route to delete it from this phone."), 12, .suave).padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 100)
            }
            VStack {
                Spacer()
                botonEmpezar
            }
            if let a = aviso {
                VStack { Spacer(); Text(a).font(.callout.weight(.semibold)).foregroundColor(.white).multilineTextAlignment(.center)
                    .padding(14).frame(maxWidth: .infinity).background(Color.panel.opacity(0.97)).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borde)).padding(.horizontal, 16).padding(.bottom, 90) }
            }
        }
        .navigationBarHidden(true)
        .task { await cargarServidor() }
        .onAppear { guardadas = Rutas.guardadas; UserDefaults.standard.set(true, forKey: "navigator_visto") }
        .onReceive(NotificationCenter.default.publisher(for: .gpxRecibido)) { n in if let a = n.object as? String { guardadas = Rutas.guardadas; abrir = a } }
        .fileImporter(isPresented: $importar, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml, .data]) { r in
            if case .success(let u) = r { abrirArchivo(u) }
        }
        .alert(t("¿Borrar la ruta del móvil?", "Esborrar la ruta del mòbil?", "Delete route from this phone?"), isPresented: Binding(get: { borrar != nil }, set: { if !$0 { borrar = nil } })) {
            Button(t("Borrar", "Esborrar", "Delete"), role: .destructive) { if let b = borrar { Rutas.borrar(b.archivo); guardadas = Rutas.guardadas } }
            Button(t("Cancelar", "Cancel·lar", "Cancel"), role: .cancel) {}
        } message: { Text(borrar?.nombre ?? "") }
    }

    private func mostrar(_ s: String) {
        withAnimation { aviso = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { withAnimation { if aviso == s { aviso = nil } } }
    }

    private var carpetas: [String] {
        let cs = Array((servidor ?? [:]).keys)
        return Rutas.orden.filter { cs.contains($0) } + cs.filter { !Rutas.orden.contains($0) }.sorted()
    }
    private var elegidaReal: String { carpetas.contains(elegida) ? elegida : (carpetas.first ?? "") }

    private func cargarServidor() async {
        cargando = true
        servidor = await Rutas.listaServidor(red: true)
        sinRed = servidor == nil
        if servidor != nil, UserDefaults.standard.data(forKey: "nav_servidor") == nil { sinRed = true }
        cargando = false
    }

    @ViewBuilder private var listaServidor: some View {
        if let s = servidor {
            let lista = s[elegidaReal] ?? []
            if lista.isEmpty {
                HStack(spacing: 12) {
                    Text("+").font(.custom("TeXGyrePagella-Bold", size: 26)).foregroundColor(Color(hex: 0x3A4A60)).frame(width: 64, height: 64)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0E1620)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Aún no hay rutas de ", "Encara no hi ha rutes de ", "No routes yet for ") + Rutas.nombrePrueba(elegidaReal)).font(.custom("TeXGyrePagella-Bold", size: 15)).foregroundColor(.texto)
                        Texto(t("La organización las subirá antes de la prueba.", "L'organització les pujarà abans de la prova.", "The organisers will upload them before the event."), 12.5, .suave)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 16).fill(Color.panel)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borde)).opacity(0.7)
                .padding(.top, 4)
            } else {
                ForEach(lista) { r in tarjeta(Rutas.delServidor(r.carpeta, r.archivo), r).padding(.top, 8) }
            }
        }
    }

    /// Una ruta: la miniatura de su forma, el nombre, km y subida, y si está guardada en el móvil.
    private func tarjeta(_ g: Rutas.Guardada?, _ r: Rutas.Remota?) -> some View {
        let carpeta = g.map { $0.carpeta.isEmpty ? "movil" : $0.carpeta } ?? r?.carpeta ?? "movil"
        let col = carpeta == "movil" || carpeta == "rider1000" ? Color(hex: 0x3AA6FF) : Rutas.colorPrueba(carpeta)
        let id = g?.archivo ?? r?.id ?? ""
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0E1620))
                if let g = g { MiniRuta(archivo: g.archivo, color: col) }
                else { Image(Rutas.iconoPrueba(r?.carpeta ?? "")).resizable().scaledToFit().padding(8).opacity(0.85) }
            }.frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(g?.nombre ?? Rutas.nombreDeArchivo(r?.archivo ?? "")).font(.custom("TeXGyrePagella-Bold", size: 16)).foregroundColor(.texto).lineLimit(2)
                if let g = g {
                    Texto(Rutas.detalle(g), 12, .suave)
                    Texto("✓  " + t("Guardada en el móvil", "Desada al mòbil", "Saved on this phone"), 12, Color(hex: 0x7FD3EA))
                } else if let r = r {
                    let kb = r.bytes > 1024 * 1024 ? String(format: "%.1f MB", Double(r.bytes) / 1048576) : "\(max(1, r.bytes / 1024)) KB"
                    Texto("⬇  " + t("Toca para descargarla", "Toca per baixar-la", "Tap to download") + " · " + kb, 12, .suave)
                }
            }
            Spacer(minLength: 0)
            if bajando == id { ProgressView().frame(width: 26, height: 26) } else { Text("›").font(.system(size: 24)).foregroundColor(.suave) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.panel))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.borde, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { tocar(g, r, id) }
        .onLongPressGesture { if let g = g { borrar = g } }
    }

    private func tocar(_ g: Rutas.Guardada?, _ r: Rutas.Remota?, _ id: String) {
        // guardada y sin cambios en el servidor (mismo tamaño): se abre ya; si la organización la ha cambiado, se baja la nueva
        if let g = g {
            let tam = (try? FileManager.default.attributesOfItem(atPath: g.fichero.path)[.size] as? Int) ?? -1
            if r == nil || sinRed || tam == r!.bytes { abrir = g.archivo; return }
        }
        guard let r = r, bajando == nil else { return }
        bajando = id
        Task {
            do {
                let d = try await Rutas.bajar(r.url)
                let nueva = try Rutas.guardar(d, nombreArchivo: r.archivo, origen: "One Second", carpetaSrv: r.carpeta, remoto: r.archivo)
                bajando = nil; guardadas = Rutas.guardadas; abrir = nueva.archivo
            } catch is Gpx.Fallo {
                bajando = nil; mostrar(t("Ese archivo no tiene ninguna ruta.", "Aquest fitxer no té cap ruta.", "That file has no route."))
            } catch {
                bajando = nil
                if let g = g { abrir = g.archivo } else { mostrar(t("No se ha podido descargar. Mira la cobertura.", "No s'ha pogut baixar. Mira la cobertura.", "Couldn't download. Check your signal.")) }
            }
        }
    }

    private func abrirArchivo(_ u: URL) {
        mostrar(t("Abriendo la ruta…", "Obrint la ruta…", "Opening the route…"))
        if let a = NavigatorView.importar(u) { guardadas = Rutas.guardadas; abrir = a } else {
            mostrar(t("Ese archivo no es una ruta GPX.", "Aquest fitxer no és una ruta GPX.", "That file is not a GPX route."))
        }
    }

    /// Guarda un GPX que llega de Archivos o compartido (WhatsApp...). Devuelve su archivo, o nil si no es una ruta.
    static func importar(_ u: URL) -> String? {
        let acceso = u.startAccessingSecurityScopedResource()
        defer { if acceso { u.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: u), d.count <= Rutas.maxBytes else { return nil }
        return try? Rutas.guardar(d, nombreArchivo: u.lastPathComponent, origen: t("Compartida", "Compartida", "Shared"), carpetaSrv: nil, remoto: nil).archivo
    }

    @ViewBuilder private var navegandoVista: some View {
        if nav.navegando {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Texto("●  " + t("NAVEGANDO", "NAVEGANT", "NAVIGATING"), 11, Color(hex: 0x7FD3EA), .medium)
                    Text(nav.nombre).font(.custom("TeXGyrePagella-Bold", size: 16)).foregroundColor(.texto)
                }
                Spacer()
                Button { nav.parar() } label: {
                    Text(t("Parar", "Aturar", "Stop")).font(.system(size: 13.5, weight: .medium)).foregroundColor(Color(hex: 0xC9D3DF))
                        .padding(.horizontal, 12).padding(.vertical, 8).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.borde))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x102846)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.azul, lineWidth: 1))
            .onTapGesture { abrir = nav.archivo }
        }
    }

    @ViewBuilder private var botonEmpezar: some View {
        if nav.navegando {
            boton("🧭   " + t("Volver al mapa", "Tornar al mapa", "Back to the map")) { abrir = nav.archivo }
        } else if let u = Rutas.ultima {
            boton("▶   " + t("Empezar a navegar", "Començar a navegar", "Start navigating") + " · " + u.nombre) { abrir = u.archivo }
        }
    }
    private func boton(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.system(size: 15.5, weight: .medium)).foregroundColor(.white).lineLimit(1).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 54).background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x2F7DE1)))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        }.buttonStyle(.plain).padding(.horizontal, 16).padding(.bottom, 12)
    }
}

/// La miniatura de la forma de una ruta guardada.
struct MiniRuta: View {
    let archivo: String
    let color: Color
    @State private var puntos: [CGPoint] = []
    var body: some View {
        Canvas { cx, size in
            guard puntos.count > 1 else { return }
            let xs = puntos.map(\.x), ys = puntos.map(\.y)
            let mnx = xs.min()!, mxx = xs.max()!, mny = ys.min()!, mxy = ys.max()!
            let esc = min((size.width - 14) / max(0.000001, mxx - mnx), (size.height - 14) / max(0.000001, mxy - mny))
            let ox = (size.width - (mxx - mnx) * esc) / 2, oy = (size.height - (mxy - mny) * esc) / 2
            var p = Path()
            for (i, q) in puntos.enumerated() {
                let v = CGPoint(x: ox + (q.x - mnx) * esc, y: oy + (mxy - q.y) * esc)
                if i == 0 { p.move(to: v) } else { p.addLine(to: v) }
            }
            cx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .task {
            guard let g = try? Rutas.abrir(archivo) else { return }
            let k = cos(g.lat[0] * .pi / 180)
            puntos = g.simplificar(30).map { CGPoint(x: g.lon[$0] * k, y: g.lat[$0]) }
        }
    }
}

extension Notification.Name { static let gpxRecibido = Notification.Name("gpxRecibido") }
