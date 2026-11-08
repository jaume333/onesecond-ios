import Foundation

/// Chat con la organización: mensajes de la organización (al piloto solo o a todos), que llegan en la respuesta a
/// los envíos de posiciones o consultando …/mensajes, y respuestas del piloto.
final class Mensajes {
    struct Linea: Identifiable { let id = UUID(); let yo: Bool; let t: Int64; let texto: String; let todos: Bool; let enviada: Bool }

    let aj: Ajustes
    private(set) var recibidos: [[String: Any]] = []   // {id, t (ms), texto, todos, leido, leido_env}
    private(set) var mios: [[String: Any]] = []        // {uid, texto, t, enviada, mensaje_id}
    private var pendientes: [[String: Any]] = []       // {uid, texto, mensaje_id}

    init(_ aj: Ajustes) {
        self.aj = aj
        recibidos = aj.json("msgs") as? [[String: Any]] ?? []
        mios = aj.json("chat_yo") as? [[String: Any]] ?? []
        pendientes = aj.json("resp_pend") as? [[String: Any]] ?? []
    }

    private func guardar() {
        aj.guardarJson("msgs", Array(recibidos.suffix(30)))
        aj.guardarJson("chat_yo", Array(mios.suffix(60)))
        aj.guardarJson("resp_pend", pendientes)
    }

    var sinLeer: Int { recibidos.filter { !$0.bool("leido") }.count }

    var lineas: [Linea] {
        var l = recibidos.map { Linea(yo: false, t: Int64($0.int("t")), texto: $0.str("texto"), todos: $0.bool("todos"), enviada: true) }
        l += mios.map { Linea(yo: true, t: Int64($0.int("t")), texto: $0.str("texto"), todos: false, enviada: $0.bool("enviada")) }
        return l.sorted { $0.t < $1.t }
    }

    /// Mensajes nuevos que han llegado del servidor: se guardan, se avisa y se confirma la recepción.
    func llegados(_ msgs: [[String: Any]]?) async {
        guard let msgs = msgs, !msgs.isEmpty else { return }
        var ack: [Int] = []
        for m in msgs {
            let id = m.int("id")
            if id <= 0 { continue }
            ack.append(id)
            if recibidos.contains(where: { $0.int("id") == id }) { continue }
            let n: [String: Any] = ["id": id, "t": Int64(m.int("t")) * 1000, "texto": m.str("texto"), "todos": m.bool("todos"), "leido": false]
            recibidos.append(n)
            Notificar.enviar(titulo: aj.p.nombre + " · " + t("Mensaje de la organización", "Missatge de l'organització", "Message from the organisers"), texto: m.str("texto"))
        }
        guardar()
        if !ack.isEmpty { _ = await http(["recibidos": ack]) }
        await enviarRespuestas()
    }

    func responder(_ texto: String) {
        let tx = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if tx.isEmpty { return }
        let uid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
        let ultimo = recibidos.last?.int("id") ?? 0
        mios.append(["uid": uid, "texto": tx, "t": ahoraMs(), "enviada": false, "mensaje_id": ultimo])
        var x: [String: Any] = ["uid": uid, "texto": tx]
        if ultimo > 0 { x["mensaje_id"] = ultimo }
        pendientes.append(x)
        guardar()
    }

    func enviarRespuestas() async {
        if pendientes.isEmpty { return }
        let lote = pendientes
        guard let d = await http(["respuestas": lote]) else { return }
        let ok = Set((Red.objeto(d)["resp_ok"] as? [Any] ?? []).map { "\($0)" })
        if ok.isEmpty { return }
        pendientes.removeAll { ok.contains($0.str("uid")) }
        for i in mios.indices where ok.contains(mios[i].str("uid")) { mios[i]["enviada"] = true }
        guardar()
    }

    /// Pregunta por mensajes nuevos (cuando se envía poco a menudo o al abrir el chat).
    func consultar() async {
        guard let d = await http(nil) else { return }
        await llegados(Red.objeto(d)["msgs"] as? [[String: Any]])
    }

    /// Al abrir el chat: todos leídos (y se le dice al servidor).
    func marcarLeidos() async {
        var ids: [Int] = []
        for i in recibidos.indices {
            if !recibidos[i].bool("leido") { recibidos[i]["leido"] = true }
            if !recibidos[i].bool("leido_env") { ids.append(recibidos[i].int("id")) }
        }
        guardar()
        if ids.isEmpty { return }
        if await http(["leidos": ids]) != nil {
            for i in recibidos.indices where ids.contains(recibidos[i].int("id")) { recibidos[i]["leido_env"] = true }
            guardar()
        }
    }

    private func http(_ cuerpo: Any?) async -> Data? {
        guard let base = aj.base else { return nil }
        let (c, d) = await Red.pedir(base + "/mensajes", cuerpo: cuerpo)
        return c == 200 ? d : nil
    }
}
