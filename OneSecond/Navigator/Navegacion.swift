import Foundation
import CoreLocation
import AVFoundation
import AudioToolbox

/// One Second Navigator: sigue la ruta con el GPS también con la pantalla bloqueada (como NavService.java).
/// Calcula los km hechos y los que faltan, la subida que queda, la próxima curva fuerte y si te has salido de la ruta
/// (más de 50 m): entonces vibra, pita y lo dice en voz alta (sale por el intercomunicador del casco si está conectado).
/// Al empezar a navegar, la prueba vinculada empieza a emitir la posición sola.
@MainActor
final class Navegacion: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Navegacion()
    static let fueraM = 50.0, vueltaM = 35.0

    @Published private(set) var ruta: Gpx? = nil
    @Published private(set) var archivo = ""
    @Published private(set) var nombre = ""
    @Published private(set) var pos: CLLocation? = nil
    @Published private(set) var rumbo: Double = .nan
    @Published private(set) var enRuta: Double = 0
    @Published private(set) var aRuta: Double = .nan
    @Published private(set) var cercano: (m: Double, d: Double, lat: Double, lon: Double, i: Int)? = nil
    @Published private(set) var fuera = false
    @Published private(set) var llegado = false
    @Published private(set) var estuvoEnRuta = false
    @Published private(set) var emite: String? = nil
    @Published var voz: Bool = UserDefaults.standard.object(forKey: "nav_voz") as? Bool ?? true {
        didSet { UserDefaults.standard.set(voz, forKey: "nav_voz"); if !voz { habla.stopSpeaking(at: .immediate) } }
    }
    var navegando: Bool { ruta != nil }

    private let lm = CLLocationManager()
    private let habla = AVSpeechSynthesizer()
    private var fueraSeguidos = 0
    private var ultimoAvisoFuera = Date.distantPast
    private var anterior: CLLocation? = nil
    private var dichos = Set<Int>()

    override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.distanceFilter = kCLDistanceFilterNone
        lm.activityType = .automotiveNavigation
        lm.pausesLocationUpdatesAutomatically = false
    }

    func empezar(_ a: String) -> Bool {
        guard let g = try? Rutas.abrir(a) else { return false }
        ruta = g; archivo = a
        nombre = Rutas.buscar(a)?.nombre ?? g.nombre
        enRuta = 0; aRuta = .nan; cercano = nil; fuera = false; llegado = false; estuvoEnRuta = false
        fueraSeguidos = 0; dichos = []; anterior = nil; pos = nil
        UserDefaults.standard.set(a, forKey: "nav_navegando")
        Rutas.tocar(a)
        if Demo.activo { return true }
        let st = lm.authorizationStatus
        if st == .notDetermined { lm.requestWhenInUseAuthorization() }
        if st == .authorizedWhenInUse || st == .authorizedAlways || st == .notDetermined {
            lm.allowsBackgroundLocationUpdates = true
            lm.showsBackgroundLocationIndicator = true
            lm.startUpdatingLocation()
        }
        // la voz por el altavoz o el intercomunicador, bajando la música mientras habla
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers, .allowBluetoothA2DP])
        emite = emitirVinculada()
        return true
    }

    /// Capturas: una ruta de ejemplo por Montserrat y una posición simulada a mitad de camino.
    func cargarDemo() -> String? {
        var pts = ""
        for i in 0...400 {
            let f = Double(i) / 400
            let la = 41.560 + 0.05 * f + 0.004 * sin(f * 40), lo = 1.780 + 0.06 * f + 0.003 * cos(f * 33)
            pts += String(format: "<trkpt lat=\"%.6f\" lon=\"%.6f\"><ele>%.0f</ele></trkpt>", la, lo, 400 + 600 * sin(f * .pi) + 40 * sin(f * 25))
        }
        let gpx = "<?xml version=\"1.0\"?><gpx version=\"1.1\"><trk><name>Ronda 2026 · CP3-CP4</name><trkseg>\(pts)</trkseg></trk></gpx>"
        guard let g = try? Rutas.guardar(Data(gpx.utf8), nombreArchivo: "Ronda_2026_CP3-CP4.gpx", origen: "One Second", carpetaSrv: "ronda", remoto: "Ronda_2026_CP3-CP4.gpx"),
              empezar(g.archivo), let r = ruta else { return nil }
        let i = r.indice(r.total * 0.42)
        estuvoEnRuta = true
        let l = CLLocation(coordinate: CLLocationCoordinate2D(latitude: r.lat[i], longitude: r.lon[i]), altitude: r.ele[i], horizontalAccuracy: 4, verticalAccuracy: 5,
                           course: Gpx.rumbo(r.lat[i], r.lon[i], r.lat[i + 3], r.lon[i + 3]), speed: 14, timestamp: Date())
        nueva(l)
        emite = "Ronda la Llana"
        return g.archivo
    }

    /// La prueba vinculada empieza a emitir la posición (devuelve su nombre, o nil).
    private func emitirVinculada() -> String? {
        let c = Central.shared
        if let e = c.emitiendo { return Prueba.de(e)?.nombre }
        guard let p = c.vinculada else { return nil }
        c.emitir(p)
        return c.emitiendo == p.id ? p.nombre : nil
    }

    func parar() {
        UserDefaults.standard.removeObject(forKey: "nav_navegando")
        lm.stopUpdatingLocation()
        lm.allowsBackgroundLocationUpdates = false
        ruta = nil; pos = nil; emite = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in if let l = locations.last { self.nueva(l) } }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let st = manager.authorizationStatus
            if self.ruta != nil && (st == .authorizedWhenInUse || st == .authorizedAlways) {
                manager.allowsBackgroundLocationUpdates = true
                manager.startUpdatingLocation()
                if self.emite == nil { self.emite = self.emitirVinculada() }
            }
        }
    }

    private func nueva(_ l: CLLocation) {
        guard let ruta = ruta, l.horizontalAccuracy >= 0 else { return }
        pos = l
        if l.course >= 0 && l.speed > 1.5 { rumbo = l.course }
        else if let a = anterior, Gpx.metros(a.coordinate.latitude, a.coordinate.longitude, l.coordinate.latitude, l.coordinate.longitude) > 8 {
            rumbo = Gpx.rumbo(a.coordinate.latitude, a.coordinate.longitude, l.coordinate.latitude, l.coordinate.longitude)
        }
        if anterior == nil || Gpx.metros(anterior!.coordinate.latitude, anterior!.coordinate.longitude, l.coordinate.latitude, l.coordinate.longitude) > 8 { anterior = l }
        situar(l.coordinate.latitude, l.coordinate.longitude)
        if l.horizontalAccuracy <= 50 { comprobarFuera() }
        if !fuera && estuvoEnRuta { proximaCurva() }
        if !llegado && estuvoEnRuta && ruta.total - enRuta < 40 && aRuta < 60 {
            llegado = true
            sonar(true)
            decir(t("Has llegado al final de la ruta.", "Has arribat al final de la ruta.", "You have reached the end of the route."))
        }
    }

    /// Dónde estamos sobre la ruta: se busca cerca de donde íbamos (así una ruta que pasa dos veces por el mismo sitio no salta).
    private func situar(_ la: Double, _ lo: Double) {
        guard let ruta = ruta else { return }
        var r: (m: Double, d: Double, lat: Double, lon: Double, i: Int)?
        if cercano == nil {
            r = ruta.cercano(la, lo, 0, ruta.n - 1)
        } else {
            r = ruta.cercano(la, lo, ruta.indice(enRuta - 400), ruta.indice(enRuta + 3000) + 1)
            if r == nil || r!.m > 80 {                      // muy lejos: se busca en toda la ruta
                if let g = ruta.cercano(la, lo, 0, ruta.n - 1), r == nil || g.m < r!.m - 30 { r = g }
            }
        }
        guard let rr = r else { return }
        cercano = rr; aRuta = rr.m; enRuta = rr.d
        if aRuta < Navegacion.vueltaM { estuvoEnRuta = true }
    }

    private func comprobarFuera() {
        guard estuvoEnRuta else { return }                   // aún vamos hacia la ruta: no se avisa
        if aRuta > Navegacion.fueraM { fueraSeguidos += 1 } else if aRuta < Navegacion.vueltaM { fueraSeguidos = 0 }
        if !fuera && fueraSeguidos >= 3 {
            fuera = true; ultimoAvisoFuera = Date(); avisoFuera()
        } else if fuera && fueraSeguidos == 0 {
            fuera = false
            sonar(true)
            decir(t("Has vuelto a la ruta.", "Has tornat a la ruta.", "Back on the route."))
        } else if fuera && Date().timeIntervalSince(ultimoAvisoFuera) > 45 {
            ultimoAvisoFuera = Date(); avisoFuera()
        }
    }

    private func avisoFuera() {
        sonar(false)
        vibrar()
        guard let p = pos else { return }
        let dir = cercano.map { Navegacion.direccion(Gpx.rumbo(p.coordinate.latitude, p.coordinate.longitude, $0.lat, $0.lon)) } ?? ""
        let m = Navegacion.metrosDichos(aRuta)
        decir(t("Te has salido de la ruta. Está a \(m), hacia el \(dir).", "T'has sortit de la ruta. És a \(m), cap al \(dir).", "You are off the route. It is \(m) to the \(dir)."))
    }

    /// La próxima curva fuerte de la ruta (para el cartel de arriba y la voz).
    var proximo: Gpx.Giro? { ruta?.giros.first { $0.d > enRuta + 10 } }

    private func proximaCurva() {
        guard let ruta = ruta, let g = proximo, g.tipo >= 2,                         // en voz solo las cerradas y las herraduras
              let id = ruta.giros.firstIndex(where: { $0.d == g.d }) else { return }
        let falta = g.d - enRuta
        if falta <= 300 && falta > 150 && dichos.insert(id * 2).inserted {
            decir(t("A ", "A ", "In ") + Navegacion.metrosDichos(falta) + ", " + Navegacion.textoGiro(g).lowercased() + ".")
        } else if falta <= 80 && dichos.insert(id * 2 + 1).inserted {
            decir(Navegacion.textoGiro(g) + ".")
        }
    }

    static func textoGiro(_ g: Gpx.Giro) -> String {
        let izq = g.lado < 0
        switch g.tipo {
        case 3: return izq ? t("Curva de herradura a la izquierda", "Revolt de ferradura a l'esquerra", "Hairpin to the left")
                           : t("Curva de herradura a la derecha", "Revolt de ferradura a la dreta", "Hairpin to the right")
        case 2: return izq ? t("Curva cerrada a la izquierda", "Revolt tancat a l'esquerra", "Sharp bend to the left")
                           : t("Curva cerrada a la derecha", "Revolt tancat a la dreta", "Sharp bend to the right")
        default: return izq ? t("Curva a la izquierda", "Revolt a l'esquerra", "Bend to the left")
                            : t("Curva a la derecha", "Revolt a la dreta", "Bend to the right")
        }
    }
    static func indice8(_ r: Double) -> Int { Int((((r.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 45).rounded()) % 8 }
    static func direccion(_ r: Double) -> String {
        let i = indice8(r)
        return t(["norte", "noreste", "este", "sureste", "sur", "suroeste", "oeste", "noroeste"][i],
                 ["nord", "nord-est", "est", "sud-est", "sud", "sud-oest", "oest", "nord-oest"][i],
                 ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][i])
    }
    static func flecha(_ r: Double) -> String { ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"][indice8(r)] }
    static func metrosDichos(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.1f km", m / 1000).replacingOccurrences(of: ".0 km", with: " km").replacingOccurrences(of: ".", with: ",") }
        return "\(Int((m / 10).rounded()) * 10)" + t(" metros", " metres", " metres")
    }

    private func sonar(_ bien: Bool) { AudioServicesPlaySystemSound(bien ? 1057 : 1005) }
    private func vibrar() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
    }
    func decir(_ s: String) {
        guard voz else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: s)
        u.voice = AVSpeechSynthesisVoice(language: ["es-ES", "ca-ES", "en-GB"][Idioma.actual]) ?? AVSpeechSynthesisVoice(language: "es-ES")
        habla.stopSpeaking(at: .immediate)
        habla.speak(u)
    }
}
