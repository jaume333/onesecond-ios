import SwiftUI
import AVFoundation

/// Vincular la prueba: escanear el QR del piloto, pegar la dirección o (Rider 1000 y Ronda) dorsal y teléfono.
struct VincularView: View {
    @EnvironmentObject var central: Central
    @Environment(\.dismiss) var cerrar
    let p: Prueba
    @State private var direccion = ""
    @State private var dorsal = ""
    @State private var telefono = ""
    @State private var error = ""
    @State private var comprobando = false
    @State private var escaneando = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.fondo.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if p.servidor != nil {
                            tarjeta {
                                Text(t("Con tu inscripción", "Amb la teva inscripció", "With your entry")).font(.headline).foregroundColor(.white)
                                Text(t("Pon tu dorsal y el teléfono que diste al inscribirte.", "Posa el dorsal i el telèfon que vas donar en inscriure't.", "Enter your number and the phone you gave when entering."))
                                    .font(.footnote).foregroundColor(.suave)
                                campo(t("Dorsal", "Dorsal", "Number"), $dorsal).keyboardType(.numberPad)
                                campo(t("Teléfono", "Telèfon", "Phone"), $telefono).keyboardType(.phonePad)
                                BotonGrande(texto: comprobando ? t("Comprobando…", "Comprovant…", "Checking…") : t("VINCULAR", "VINCULAR", "LINK"), color: .oro, textoColor: .black) { porDorsal() }
                                    .disabled(comprobando)
                            }
                        }
                        tarjeta {
                            Text(t("Con el QR de la organización", "Amb el QR de l'organització", "With the organisers' QR")).font(.headline).foregroundColor(.white)
                            BotonGrande(texto: "📷  " + t("ESCANEAR EL QR", "ESCANEJAR EL QR", "SCAN THE QR"), color: .panel, textoColor: .white) { escaneando = true }
                        }
                        tarjeta {
                            Text(t("Pegando tu dirección de piloto", "Enganxant la teva adreça de pilot", "Pasting your rider address")).font(.headline).foregroundColor(.white)
                            campo("https://onesecond.es/…/api/p/…", $direccion).keyboardType(.URL).textInputAutocapitalization(.never).disableAutocorrection(true)
                            HStack(spacing: 10) {
                                Button(t("Pegar", "Enganxar", "Paste")) { direccion = UIPasteboard.general.string ?? "" }
                                    .buttonStyle(.bordered)
                                BotonGrande(texto: t("GUARDAR", "DESAR", "SAVE"), color: .oro, textoColor: .black) { guardar(direccion) }
                            }
                        }
                        if !error.isEmpty { Text(error).font(.callout.weight(.semibold)).foregroundColor(.rojo) }
                    }.padding(16)
                }
            }
            .navigationTitle(t("Vincular ", "Vincular ", "Link ") + p.nombre)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Cancelar", "Cancel·lar", "Cancel")) { cerrar() } } }
            .sheet(isPresented: $escaneando) {
                EscanerQR { texto in
                    escaneando = false
                    guardar(extraer(texto))
                }.ignoresSafeArea()
            }
        }
    }

    /// El QR puede llevar la dirección tal cual o el enlace onesecondgps://configurar?u=…
    private func extraer(_ s: String) -> String {
        if let c = URLComponents(string: s), let u = c.queryItems?.first(where: { $0.name == "u" })?.value, Prueba.deEsquema(c.scheme ?? "") != nil { return u }
        return s
    }

    private func guardar(_ u: String) {
        if let e = central.vincular(p, url: u) { error = e; return }
        central.breve(t("Vinculada con tu inscripción ✓", "Vinculada amb la teva inscripció ✓", "Linked to your entry ✓"))
        cerrar()
    }

    private func porDorsal() {
        let d = dorsal.trimmingCharacters(in: .whitespaces), te = telefono.trimmingCharacters(in: .whitespaces)
        if d.isEmpty || te.filter(\.isNumber).count < 9 {
            error = t("Pon el dorsal y un teléfono de 9 cifras.", "Posa el dorsal i un telèfon de 9 xifres.", "Enter your number and a 9-digit phone."); return
        }
        comprobando = true; error = ""
        Task {
            let e = await central.vincularDorsal(p, dorsal: d, telefono: te)
            comprobando = false
            if let e = e { error = e } else {
                central.breve(t("Vinculada con tu inscripción ✓", "Vinculada amb la teva inscripció ✓", "Linked to your entry ✓"))
                cerrar()
            }
        }
    }

    private func tarjeta<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10, content: c).padding(16).background(Color.panel).cornerRadius(14)
    }
    private func campo(_ h: String, _ b: Binding<String>) -> some View {
        TextField(h, text: b).padding(12).background(Color.fondo).cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borde)).foregroundColor(.white)
    }
}

/// Lector de QR con la cámara.
struct EscanerQR: UIViewControllerRepresentable {
    let leido: (String) -> Void
    func makeUIViewController(context: Context) -> Controlador { let c = Controlador(); c.leido = leido; return c }
    func updateUIViewController(_ c: Controlador, context: Context) {}

    final class Controlador: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var leido: ((String) -> Void)?
        private let sesion = AVCaptureSession()
        private var hecho = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let disp = AVCaptureDevice.default(for: .video), let entrada = try? AVCaptureDeviceInput(device: disp),
                  sesion.canAddInput(entrada) else {
                let l = UILabel(); l.text = t("No se puede usar la cámara.", "No es pot fer servir la càmera.", "Camera not available."); l.textColor = .white
                l.frame = view.bounds; l.textAlignment = .center; view.addSubview(l); return
            }
            sesion.addInput(entrada)
            let salida = AVCaptureMetadataOutput()
            if sesion.canAddOutput(salida) {
                sesion.addOutput(salida)
                salida.setMetadataObjectsDelegate(self, queue: .main)
                salida.metadataObjectTypes = [.qr]
            }
            let capa = AVCaptureVideoPreviewLayer(session: sesion)
            capa.frame = view.layer.bounds
            capa.videoGravity = .resizeAspectFill
            view.layer.addSublayer(capa)
            DispatchQueue.global(qos: .userInitiated).async { self.sesion.startRunning() }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if sesion.isRunning { sesion.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objs: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hecho, let o = objs.first as? AVMetadataMachineReadableCodeObject, let s = o.stringValue else { return }
            hecho = true
            sesion.stopRunning()
            leido?(s)
        }
    }
}
