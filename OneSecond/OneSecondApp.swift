import SwiftUI

@main
struct OneSecondApp: App {
    @StateObject private var central = Central.shared
    @StateObject private var cuenta = Cuenta.shared
    @State private var abierta: Prueba? = nil

    var body: some Scene {
        WindowGroup {
            SelectorView(abierta: $abierta)
                .environmentObject(central)
                .environmentObject(cuenta)
                .preferredColorScheme(.dark)
                .onAppear {
                    if Demo.activo {
                        switch Demo.pantalla { case 2, 3, 4: abierta = .ronda; case 5: abierta = .rally; default: break }
                    }
                }
                // botón «Configurar la app» de la web: onesecondgps://configurar?u=<dirección del piloto>
                .onOpenURL { url in
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
