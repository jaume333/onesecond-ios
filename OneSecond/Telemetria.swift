import Foundation

/// Telemetría gratuita de Ronda la Llana y Rider 1000 (como Telemetria.java de Android 1.57):
/// el día de la prueba, 2 h antes de la salida, la app empieza a emitir sola al abrirla (si está vinculada
/// y no se ha parado a mano ese día). Antes de ese día dice cuándo empezará.
enum Telemetria {
    private static var d: UserDefaults { .standard }

    static func hoy() -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = Cuenta.madrid
        let k = cal.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", k.year ?? 0, k.month ?? 0, k.day ?? 0)
    }

    static func esDeTelemetria(_ p: Prueba) -> Bool { p.id == "ronda" || p.id == "rider" }

    private static func suyos(_ p: Prueba) -> [[String: Any]] {
        Cuenta.shared.eventos.filter { Prueba.deCuentas($0.str("app"))?.id == p.id }
    }

    /// La prueba de hoy de esta app, o nil.
    static func eventoDeHoy(_ p: Prueba) -> [String: Any]? {
        let h = hoy()
        return suyos(p).first { $0.str("fecha").hasPrefix(h) }
    }

    /// La próxima prueba de esta app (hoy o más adelante), o nil.
    static func proxima(_ p: Prueba) -> [String: Any]? {
        let h = hoy()
        return suyos(p).filter { String($0.str("fecha").prefix(10)) >= h }.min { $0.str("fecha") < $1.str("fecha") }
    }

    /// Hoy es el día de una prueba de esta app (o el móvil aún no sabe de ninguna: como antes, sin esperar).
    static func diaDeEmitir(_ p: Prueba) -> Bool {
        eventoDeHoy(p) != nil || suyos(p).isEmpty
    }

    /// «Sábado 7 de noviembre» (hora de Madrid).
    static func fechaTxt(_ ev: [String: Any]) -> String {
        guard let s = Cuenta.salida(ev) else { return "" }
        let f = DateFormatter()
        f.locale = Idioma.locale; f.timeZone = Cuenta.madrid
        f.dateFormat = Idioma.actual == 0 ? "EEEE d 'de' MMMM" : "EEEE d MMMM"
        let x = f.string(from: s)
        return x.prefix(1).uppercased() + x.dropFirst()
    }

    /// «Emitirá sola el sábado 7 de noviembre, al abrir la app.»
    static func soloElDia(_ p: Prueba) -> String {
        let f = proxima(p).map(fechaTxt) ?? ""
        if f.isEmpty {
            return t("Emitirá sola el día de la prueba, al abrir la app.", "Emetrà sola el dia de la prova, en obrir l'app.",
                     "It will start sharing by itself on event day, when you open the app.")
        }
        let m = f.prefix(1).lowercased() + f.dropFirst()
        return t("Emitirá sola el " + m + ", al abrir la app.", "Emetrà sola el " + m + ", en obrir l'app.",
                 "It will start sharing by itself on " + f + ", when you open the app.")
    }

    static func marcarParado(_ p: Prueba) { d.set(true, forKey: "tel_parado_\(p.id)_\(hoy())") }
    static func paradoHoy(_ p: Prueba) -> Bool { d.bool(forKey: "tel_parado_\(p.id)_\(hoy())") }
    static func marcarAuto(_ p: Prueba) { d.set(true, forKey: "tel_auto_\(p.id)_\(hoy())") }
    static func autoHoy(_ p: Prueba) -> Bool { d.bool(forKey: "tel_auto_\(p.id)_\(hoy())") }

    /// ¿Toca empezar a emitir sola ahora? (día de la prueba, 2 h antes de la salida, vinculada, sin parar a mano)
    @MainActor static func tocaEmitir(_ p: Prueba, _ central: Central) -> Bool {
        guard esDeTelemetria(p), central.emitiendo == nil, central.aj(p).vinculada, !paradoHoy(p),
              let ev = eventoDeHoy(p), let s = Cuenta.salida(ev) else { return false }
        return Date() >= s.addingTimeInterval(-2 * 3600)
    }

    /// Al abrir la app o la pantalla de la prueba: si toca, empieza a emitir sola. Devuelve true si ha empezado.
    @MainActor @discardableResult static func autoEmitir(_ central: Central) -> Bool {
        if Demo.activo { return false }
        for p in Prueba.todas where tocaEmitir(p, central) {
            marcarAuto(p)
            central.emitir(p)
            return true
        }
        return false
    }
}
