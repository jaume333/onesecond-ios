import SwiftUI

@main
struct OneSecondApp: App {
    @StateObject private var central = Central.shared
    @State private var abierta: Prueba? = nil

    var body: some Scene {
        WindowGroup {
            SelectorView(abierta: $abierta)
                .environmentObject(central)
                .preferredColorScheme(.dark)
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
