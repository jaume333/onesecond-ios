import SwiftUI

@main
struct OneSecondApp: App {
    @UIApplicationDelegateAdaptor(AppDelegado.self) private var delegado
    @StateObject private var central = Central.shared
    @StateObject private var cuenta = Cuenta.shared
    @State private var abierta: Prueba? = nil
    @State private var navAbierto = false

    var body: some Scene {
        WindowGroup {
            SelectorView(abierta: $abierta, navAbierto: $navAbierto)
                .environmentObject(central)
                .environmentObject(cuenta)
                .preferredColorScheme(.dark)
                .onAppear {
                    if Demo.activo {
                        switch Demo.pantalla { case 2, 3, 4: abierta = .ronda; case 5: abierta = .rally; case 12: abierta = .rider; case 13: abierta = .rally; default: break }
                    }
                }
                // «Navegar este tramo» (fichas de la Ronda): abre el Navigator con la ruta
                .onReceive(NotificationCenter.default.publisher(for: .abrirRuta)) { n in
                    guard let a = n.object as? String else { return }
                    abierta = nil
                    navAbierto = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NotificationCenter.default.post(name: .gpxRecibido, object: a) }
                }
                .onAppear { Telemetria.autoEmitir(central) }
                // aviso de una prueba en la que ya estás inscrito: se abre esa prueba
                .onReceive(NotificationCenter.default.publisher(for: .abrirPruebaDe)) { n in
                    if let a = n.object as? String, let p = Prueba.deCuentas(a) { navAbierto = false; abierta = p }
                }
                // botón «Configurar la app» de la web: onesecondgps://configurar?u=<dirección del piloto>
                .onOpenURL { url in
                    // un GPX compartido (WhatsApp, Archivos...): se guarda en el Navigator y se abre
                    if url.isFileURL {
                        if let a = NavigatorView.importar(url) {
                            abierta = nil
                            navAbierto = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NotificationCenter.default.post(name: .gpxRecibido, object: a) }
                        } else {
                            central.breve(t("Ese archivo no es una ruta GPX.", "Aquest fitxer no és una ruta GPX.", "That file is not a GPX route."), error: true)
                        }
                        return
                    }
                    guard let p = Prueba.deEsquema(url.scheme ?? ""),
                          let u = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "u" })?.value
                    else { return }
                    let destino = Prueba.deQuien(u) ?? p
                    if let e = central.vincular(destino, url: u) { central.breve(e, error: true) }
                    else { central.breve(t("Vinculada con tu inscripción ✓", "Vinculada amb la teva inscripció ✓", "Linked to your entry ✓")) }
                    abierta = destino
                }
        }
    }
}
