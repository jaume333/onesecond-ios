import Foundation

/// Peticiones al servidor de One Second (JSON).
enum Red {
    static let sesion: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 20
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Devuelve (código HTTP, cuerpo). Código -1 si no hay red.
    static func pedir(_ url: String, cuerpo: Any? = nil, texto: String? = nil) async -> (Int, Data) {
        guard let u = URL(string: url) else { return (-1, Data()) }
        var r = URLRequest(url: u)
        if let texto = texto {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = texto.data(using: .utf8)
        } else if let cuerpo = cuerpo {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: cuerpo)
        }
        do {
            let (data, resp) = try await sesion.data(for: r)
            return ((resp as? HTTPURLResponse)?.statusCode ?? -1, data)
        } catch {
            return (-1, Data())
        }
    }

    static func objeto(_ d: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }
}

extension Dictionary where Key == String, Value == Any {
    func int(_ k: String, _ def: Int = 0) -> Int {
        if let v = self[k] as? Int { return v }
        if let v = self[k] as? Int64 { return Int(v) }
        if let v = self[k] as? NSNumber { return v.intValue }
        if let v = self[k] as? Double { return Int(v) }
        if let v = self[k] as? String, let i = Int(v) { return i }
        return def
    }
    func dbl(_ k: String, _ def: Double = .nan) -> Double {
        if let v = self[k] as? Double { return v }
        if let v = self[k] as? Int { return Double(v) }
        return def
    }
    func str(_ k: String) -> String {
        if let v = self[k] as? String { return v }
        if let v = self[k], !(v is NSNull) { return "\(v)" }
        return ""
    }
    func bool(_ k: String, _ def: Bool = false) -> Bool {
        if let v = self[k] as? Bool { return v }
        if let v = self[k] as? Int { return v != 0 }
        return def
    }
}

func ahoraMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
