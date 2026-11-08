import Foundation

/// Posiciones pendientes de enviar, guardadas en un archivo (no se pierden sin cobertura ni si se cierra la app).
final class Cola {
    private let archivo: URL
    private var lineas: [String] = []

    init(_ id: String) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        archivo = dir.appendingPathComponent("cola_\(id).txt")
        if let s = try? String(contentsOf: archivo, encoding: .utf8) {
            lineas = s.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        }
    }

    func anadir(_ l: String) {
        lineas.append(l)
        if let h = try? FileHandle(forWritingTo: archivo) {
            h.seekToEndOfFile()
            h.write((l + "\n").data(using: .utf8)!)
            try? h.close()
        } else {
            guardar()
        }
    }

    func primeras(_ n: Int) -> [String] { Array(lineas.prefix(n)) }

    func quitar(_ n: Int) {
        lineas.removeFirst(min(n, lineas.count))
        guardar()
    }

    var tamano: Int { lineas.count }

    private func guardar() {
        let s = lineas.map { $0 + "\n" }.joined()
        try? s.write(to: archivo, atomically: true, encoding: .utf8)
    }
}
