import Foundation
import UIKit

/// Peticiones al servidor de One Second (JSON).
enum Red {
    static let sesion: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 20
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = ["User-Agent": agente]
        return URLSession(configuration: c)
    }()

    /// «OneSecond-iOS/1.58 (iPhone 13; iOS 17.5)»: así el panel de la organización sabe que el piloto lleva un iPhone.
    static let agente: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return "OneSecond-iOS/" + v + " (" + modelo + "; iOS " + UIDevice.current.systemVersion + ")"
    }()

    static var modelo: String {
        var u = utsname(); uname(&u)
        let id = withUnsafeBytes(of: &u.machine) { b in String(decoding: b.prefix { $0 != 0 }, as: UTF8.self) }
        let n: [String: String] = [
            "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE",
            "iPhone9,1": "iPhone 7", "iPhone9,3": "iPhone 7", "iPhone9,2": "iPhone 7 Plus", "iPhone9,4": "iPhone 7 Plus",
            "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X", "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
            "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR", "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE 2", "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max", "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE 3", "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
        ]
        return n[id] ?? (id.hasPrefix("iPhone") ? id : "iPhone")
    }

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
