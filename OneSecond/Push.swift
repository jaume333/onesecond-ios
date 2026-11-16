import SwiftUI
import UserNotifications

/// 1.62: AVISOS DE NUEVOS EVENTOS (notificaciones push de Apple). La organización pulsa «📲 Avisar a las apps» en la
/// gestión de eventos de onesecond.es/cuenta y llega a los iPhone con la app (con permiso de notificaciones y el
/// interruptor «Avisos de nuevos eventos» encendido). El servidor solo guarda el identificador del móvil y su idioma.
enum Push {
    static var activos: Bool {
        get { UserDefaults.standard.object(forKey: "push_activos") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "push_activos") }
    }

    /// Pide permiso (la primera vez) y el identificador a Apple; llega a AppDelegado.didRegister… y se manda al servidor.
    static func registrar() {
        if Demo.activo { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { si, _ in
            DispatchQueue.main.async {
                if si { UIApplication.shared.registerForRemoteNotifications() }
                else if let t = UserDefaults.standard.string(forKey: "push_token") { Task { await enviar(t, activo: false) } }
            }
        }
    }

    static func poner(_ si: Bool) {
        activos = si
        if let t = UserDefaults.standard.string(forKey: "push_token"), !si { Task { await enviar(t, activo: false) } }
        else { registrar() }
    }

    static func recibido(_ datos: Data) {
        let t = datos.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(t, forKey: "push_token")
        Task { await enviar(t, activo: activos) }
    }

    static func enviar(_ token: String, activo: Bool) async {
        var c: [String: Any] = ["token": token, "plataforma": "ios", "idioma": Idioma.codigo, "activo": activo]
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { c["version"] = v }
        let ses = await MainActor.run { Cuenta.shared.token }
        _ = await Cuenta.pedir("POST", "/api/push/registro", cuerpo: c, token: ses.isEmpty ? nil : ses)
    }
}
