import Foundation
import UserNotifications

/// Avisos de incidencias del piloto a la organización (pinchazo, avería, gasolina, perdido, abandono, accidente...).
/// Se guardan en el móvil y se envían en cuanto hay red; la organización responde y cambia su estado.
final class Avisos {
    static let tipos = ["pinchazo", "averia", "gasolina", "perdido", "abandono", "otro"]

    static func nombre(_ tipo: String) -> String {
        switch tipo {
        case "pinchazo": return t("Pinchazo", "Punxada", "Puncture")
        case "averia": return t("Avería", "Avaria", "Breakdown")
        case "gasolina": return t("Sin gasolina", "Sense benzina", "Out of fuel")
        case "perdido": return t("Me he perdido", "M'he perdut", "I'm lost")
        case "abandono": return t("Abandono", "Abandonament", "Retiring")
        case "accidente": return t("Caída / accidente", "Caiguda / accident", "Crash / accident")
        default: return t("Otro", "Altre", "Other")
        }
    }

    static func icono(_ tipo: String) -> String {
        switch tipo {
        case "pinchazo": return "🛞"
        case "averia": return "🔧"
        case "gasolina": return "⛽"
        case "perdido": return "🧭"
        case "abandono": return "🏳️"
        case "accidente": return "⚠️"
        default: return "💬"
        }
    }

    static func estadoTexto(_ e: String) -> String {
        switch e {
        case "": return t("Pendiente de enviar", "Pendent d'enviar", "Waiting to send")
        case "nuevo": return t("Enviado: la organización lo ha recibido", "Enviat: l'organització l'ha rebut", "Sent: received by the organisers")
        case "visto": return t("Visto por la organización", "Vist per l'organització", "Seen by the organisers")
        case "atendido": return t("Atendido por la organización", "Atès per l'organització", "Handled by the organisers")
        case "cancelado": return t("Cancelado", "Cancel·lat", "Cancelled")
        case "borrado_org": return t("Cerrado por la organización", "Tancat per l'organització", "Closed by the organisers")
        default: return e
        }
    }

    let aj: Ajustes
    private(set) var lista: [[String: Any]] = []

    init(_ aj: Ajustes) {
        self.aj = aj
        lista = aj.json("avisos") as? [[String: Any]] ?? []
        // solo los de las últimas 24 horas
        let lim = ahoraMs() - 24 * 3600 * 1000
        lista = lista.filter { Int64($0.int("time")) > lim }
    }

    private func guardar() { aj.guardarJson("avisos", lista) }

    func cargarDemo() {
        lista = [["id": "demo1", "tipo": "pinchazo", "texto": "Rueda trasera, estoy en el arcén", "time": ahoraMs() - 1_200_000,
                  "enviado": true, "estado": "atendido", "respuesta": "Recibido. La asistencia llega en 15 minutos."]]
    }

    func nuevo(tipo: String, texto: String, pos: (Double, Double, Double)?) {
        var o: [String: Any] = ["id": String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(18)),
                                "tipo": tipo, "texto": texto.trimmingCharacters(in: .whitespacesAndNewlines),
                                "time": ahoraMs(), "enviado": false, "estado": "", "respuesta": ""]
        if let p = pos { o["lat"] = p.0; o["lon"] = p.1; o["acc"] = p.2 }
        lista.append(o)
        guardar()
    }

    static func cerrado(_ o: [String: Any]) -> Bool {
        let e = o.str("estado")
        return e == "atendido" || e == "borrado_org" || e == "cancelado"
    }

    var hayPendientes: Bool {
        lista.contains { !$0.bool("enviado") || $0.bool("borrar") || !Avisos.cerrado($0) }
    }

    /// El piloto quita un aviso: si no se había enviado o ya está cerrado se borra; si no, se cancela en el servidor.
    func quitar(_ id: String) {
        var q: [[String: Any]] = []
        for var o in lista {
            if o.str("id") == id {
                if !o.bool("enviado") || Avisos.cerrado(o) { continue }
                o["borrar"] = true
            }
            q.append(o)
        }
        lista = q
        guardar()
    }

    /// Envía los pendientes, cancela los borrados y consulta el estado y la respuesta de la organización.
    func sincronizar() async {
        guard let base = aj.base else { return }
        var cambiado = false
        var quedan: [[String: Any]] = []
        for o in lista {
            if o.bool("borrar") {
                let (c, _) = await Red.pedir(base + "/aviso/" + o.str("id") + "/cancelar", texto: "{}")
                if c == 200 { cambiado = true; continue }
            }
            quedan.append(o)
        }
        for i in quedan.indices where !quedan[i].bool("enviado") && !quedan[i].bool("borrar") {
            var envio = quedan[i]
            envio.removeValue(forKey: "enviado"); envio.removeValue(forKey: "estado"); envio.removeValue(forKey: "respuesta")
            let (c, d) = await Red.pedir(base + "/aviso", cuerpo: envio)
            if c == 200 {
                quedan[i]["enviado"] = true
                quedan[i]["estado"] = "nuevo"
                let tel = Red.objeto(d).str("tel_org")
                if !tel.isEmpty { aj.telOrg = tel }
                cambiado = true
            }
        }
        lista = quedan
        if cambiado { guardar() }
        await consultar()
    }

    func consultar() async {
        guard let base = aj.base, lista.contains(where: { $0.bool("enviado") }) else { return }
        let (c, d) = await Red.pedir(base + "/avisos")
        guard c == 200 else { return }
        let res = Red.objeto(d)
        let tel = res.str("tel_org")
        if !tel.isEmpty { aj.telOrg = tel }
        guard let srv = res["avisos"] as? [[String: Any]] else { return }
        var cambiado = false
        for i in lista.indices {
            let id = lista[i].str("id")
            if let s = srv.first(where: { $0.str("local") == id }) {
                let est = s.str("estado"), resp = s.str("respuesta")
                if !resp.isEmpty && resp != lista[i].str("respuesta") {
                    Notificar.enviar(titulo: t("Respuesta de la organización", "Resposta de l'organització", "Reply from the organisers") + " · " + Avisos.nombre(lista[i].str("tipo")), texto: resp)
                }
                if est != lista[i].str("estado") || resp != lista[i].str("respuesta") {
                    lista[i]["estado"] = est; lista[i]["respuesta"] = resp; cambiado = true
                }
            } else if lista[i].bool("enviado") && !lista[i].bool("borrar") && lista[i].str("estado") != "borrado_org"
                        && ahoraMs() - Int64(lista[i].int("time")) < 23 * 3600 * 1000 {
                lista[i]["estado"] = "borrado_org"; cambiado = true
            }
        }
        if cambiado { guardar() }
    }
}

enum Notificar {
    static func pedirPermiso() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    static func enviar(titulo: String, texto: String) {
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = texto
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
