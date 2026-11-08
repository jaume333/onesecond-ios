import SwiftUI
import AuthenticationServices
import CryptoKit

// «Continuar con Google» e «Iniciar sesión con Apple»: entran en la misma cuenta de onesecond.es.
// Google: con el navegador seguro del sistema (ASWebAuthenticationSession) y el ID de cliente iOS que da /api/config.
// Apple: con el botón del sistema; el servidor comprueba el token con las claves de Apple.

extension Cuenta {
    /// Lo que dice /api/config sobre los botones (se guarda para que salgan al momento la próxima vez).
    static var googleIOS: String {
        get { UserDefaults.standard.string(forKey: "google_ios") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "google_ios") }
    }

    static func cargarConfig() async {
        let r = await pedir("GET", "/api/config")
        if r.codigo == 200 { googleIOS = r.json.str("google_ios") }
    }

    /// Entra con el resultado de Google o Apple. Devuelve nil si ha entrado, o el error para enseñar.
    func entrarCon(_ ruta: String, cuerpo: [String: Any]) async -> String? {
        var c = cuerpo
        c["idioma"] = Idioma.codigo
        let r = await Cuenta.pedir("POST", ruta, cuerpo: c)
        if r.codigo == 200, let tk = r.token, !tk.isEmpty {
            let u = r.json["usuario"] as? [String: Any]
            entrarConToken(tk, email: u?.str("email") ?? "")
            await actualizar()
            return nil
        }
        if r.codigo == -1 { return t("Sin conexión. Comprueba los datos móviles o el wifi.", "Sense connexió. Comprova les dades mòbils o el wifi.", "No connection. Check mobile data or wifi.") }
        switch r.json.str("codigo") {
        case "demasiados_intentos": return t("Demasiados intentos. Espera unos minutos.", "Massa intents. Espera uns minuts.", "Too many attempts. Wait a few minutes.")
        case "google_otra_cuenta", "apple_otra_cuenta":
            return t("Ese correo ya está unido a otra cuenta.", "Aquest correu ja està unit a un altre compte.", "That email is already linked to another account.")
        case "apple_sin_email":
            return t("Apple no ha dado el correo. Entra con tu correo y contraseña.", "Apple no ha donat el correu. Entra amb el teu correu i contrasenya.", "Apple didn't share your email. Sign in with email and password.")
        default: return t("No se ha podido entrar. Inténtalo otra vez.", "No s'ha pogut entrar. Torna-ho a provar.", "Couldn't sign in. Please try again.")
        }
    }
}

/// Google con PKCE (sin contraseñas ni secretos en la app).
final class GoogleLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleLogin()
    private var sesion: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }.first ?? ASPresentationAnchor()
    }

    private static func b64u(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Devuelve el «ID token» de Google, o nil si se cancela o falla.
    @MainActor func idToken(clienteID cid: String) async -> String? {
        // com.googleusercontent.apps.XXXX = el ID de cliente al revés: así Google vuelve a la app
        let partes = cid.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let esquema = "com.googleusercontent.apps." + partes
        let redirige = esquema + ":/oauth2redirect"
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verificador = Self.b64u(Data(bytes))
        let reto = Self.b64u(Data(SHA256.hash(data: Data(verificador.utf8))))
        let estado = UUID().uuidString
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: cid), .init(name: "redirect_uri", value: redirige),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: reto), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: estado), .init(name: "prompt", value: "select_account"),
        ]
        guard let url = c.url else { return nil }
        let vuelta: URL? = await withCheckedContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: esquema) { u, _ in cont.resume(returning: u) }
            s.presentationContextProvider = self
            sesion = s
            if !s.start() { cont.resume(returning: nil) }
        }
        sesion = nil
        guard let v = vuelta, let q = URLComponents(url: v, resolvingAgainstBaseURL: false)?.queryItems,
              q.first(where: { $0.name == "state" })?.value == estado,
              let codigo = q.first(where: { $0.name == "code" })?.value else { return nil }
        // Cambiar el código por el token (cliente iOS: sin secreto, con el verificador PKCE)
        var r = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var f = URLComponents()
        f.queryItems = [.init(name: "client_id", value: cid), .init(name: "code", value: codigo),
                        .init(name: "code_verifier", value: verificador), .init(name: "redirect_uri", value: redirige),
                        .init(name: "grant_type", value: "authorization_code")]
        r.httpBody = f.percentEncodedQuery?.data(using: .utf8)
        guard let (d, _) = try? await URLSession.shared.data(for: r) else { return nil }
        let tk = Red.objeto(d).str("id_token")
        return tk.isEmpty ? nil : tk
    }
}

/// Los dos botones, para la pantalla de entrar.
struct BotonesSociales: View {
    @EnvironmentObject var cuenta: Cuenta
    @Environment(\.colorScheme) var esquema
    @State private var googleID = Cuenta.googleIOS
    @Binding var ayuda: String
    @Binding var entrando: Bool
    var hecho: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.continue) { pet in
                pet.requestedScopes = [.fullName, .email]
            } onCompletion: { res in
                guard case .success(let a) = res, let cred = a.credential as? ASAuthorizationAppleIDCredential,
                      let d = cred.identityToken, let tk = String(data: d, encoding: .utf8) else {
                    if case .failure(let e) = res, (e as? ASAuthorizationError)?.code == .canceled { return }
                    ayuda = t("No se ha podido entrar con Apple.", "No s'ha pogut entrar amb Apple.", "Couldn't sign in with Apple."); return
                }
                entrar("/api/apple", ["token": tk, "nombre": cred.fullName?.givenName ?? "", "apellidos": cred.fullName?.familyName ?? ""])
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48).cornerRadius(10)

            if !googleID.isEmpty {
                Button {
                    Task {
                        guard let tk = await GoogleLogin.shared.idToken(clienteID: googleID) else { return }
                        entrar("/api/google", ["credential": tk])
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("G").font(.system(size: 20, weight: .bold)).foregroundColor(Color(hex: 0x4285F4))
                        Text(t("Continuar con Google", "Continua amb Google", "Continue with Google")).font(.system(size: 17, weight: .semibold)).foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity).frame(height: 48).background(Color.white).cornerRadius(10)
                }
                .disabled(entrando)
            }
        }
        .task {
            await Cuenta.cargarConfig()
            googleID = Cuenta.googleIOS
        }
    }

    private func entrar(_ ruta: String, _ cuerpo: [String: Any]) {
        entrando = true; ayuda = t("Entrando…", "Entrant…", "Signing in…")
        Task {
            let err = await cuenta.entrarCon(ruta, cuerpo: cuerpo)
            entrando = false
            if let err = err { ayuda = err } else { ayuda = ""; hecho() }
        }
    }
}
