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
/// 1.60: pide el permiso si hace falta (y si está denegado, lleva a Ajustes), recuadro para apuntar, linterna,
/// botón Cancelar, vibración al leer y vuelve a arrancar la cámara si el sistema la corta.
struct EscanerQR: UIViewControllerRepresentable {
    let leido: (String) -> Void
    func makeUIViewController(context: Context) -> Controlador { let c = Controlador(); c.leido = leido; return c }
    func updateUIViewController(_ c: Controlador, context: Context) {}

    final class Controlador: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var leido: ((String) -> Void)?
        private let sesion = AVCaptureSession()
        private var hecho = false
        private var capa: AVCaptureVideoPreviewLayer?
        private var disp: AVCaptureDevice?
        private let marco = UIView()
        private let texto = UILabel()
        private let linterna = UIButton(type: .system)
        private let cancelar = UIButton(type: .system)
        private var obs: [NSObjectProtocol] = []

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            texto.textColor = .white; texto.textAlignment = .center; texto.numberOfLines = 0
            texto.font = .systemFont(ofSize: 16, weight: .semibold)
            texto.text = t("Apunta al QR", "Apunta al QR", "Point at the QR code")
            marco.layer.borderColor = UIColor(red: 0.94, green: 0.81, blue: 0.6, alpha: 1).cgColor
            marco.layer.borderWidth = 4; marco.layer.cornerRadius = 16; marco.isUserInteractionEnabled = false
            for (b, s) in [(cancelar, t("Cancelar", "Cancel·lar", "Cancel")), (linterna, "🔦 " + t("Linterna", "Llanterna", "Torch"))] {
                b.setTitle(s, for: .normal); b.setTitleColor(.white, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
                b.backgroundColor = UIColor(white: 0, alpha: 0.55); b.layer.cornerRadius = 12
                b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
            }
            cancelar.addTarget(self, action: #selector(salir), for: .touchUpInside)
            linterna.addTarget(self, action: #selector(luz), for: .touchUpInside)
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: montar()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { si in DispatchQueue.main.async { si ? self.montar() : self.sinPermiso() } }
            default: sinPermiso()
            }
            [marco, texto, linterna, cancelar].forEach { view.addSubview($0) }
            // si el sistema corta la cámara (llamada, otra app…), al volver se arranca otra vez
            obs.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let s = self, !s.hecho, s.capa != nil, !s.sesion.isRunning else { return }
                DispatchQueue.global(qos: .userInitiated).async { s.sesion.startRunning() }
            })
        }
        deinit { obs.forEach { NotificationCenter.default.removeObserver($0) } }

        private func montar() {
            guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video),
                  let entrada = try? AVCaptureDeviceInput(device: d), sesion.canAddInput(entrada) else {
                texto.text = t("No se puede usar la cámara.", "No es pot fer servir la càmera.", "Camera not available."); linterna.isHidden = true; return
            }
            disp = d
            linterna.isHidden = !d.hasTorch
            sesion.addInput(entrada)
            let salida = AVCaptureMetadataOutput()
            if sesion.canAddOutput(salida) {
                sesion.addOutput(salida)
                salida.setMetadataObjectsDelegate(self, queue: .main)
                salida.metadataObjectTypes = [.qr]
            }
            // enfoque continuo de cerca (tickets) si el móvil lo permite
            if (try? d.lockForConfiguration()) != nil {
                if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
                if d.isAutoFocusRangeRestrictionSupported { d.autoFocusRangeRestriction = .near }
                d.unlockForConfiguration()
            }
            let c = AVCaptureVideoPreviewLayer(session: sesion)
            c.videoGravity = .resizeAspectFill
            view.layer.insertSublayer(c, at: 0)
            capa = c
            view.setNeedsLayout()
            DispatchQueue.global(qos: .userInitiated).async { self.sesion.startRunning() }
        }

        private func sinPermiso() {
            texto.text = t("No hay permiso para usar la cámara.\nActívalo en Ajustes › One Second › Cámara.",
                           "No hi ha permís per fer servir la càmera.\nActiva'l a Configuració › One Second › Càmera.",
                           "Camera access is off.\nTurn it on in Settings › One Second › Camera.")
            linterna.setTitle(t("Abrir Ajustes", "Obrir Configuració", "Open Settings"), for: .normal)
            linterna.removeTarget(self, action: #selector(luz), for: .touchUpInside)
            linterna.addTarget(self, action: #selector(ajustes), for: .touchUpInside)
            linterna.isHidden = false
            marco.isHidden = true
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            let b = view.bounds, lado = min(b.width, b.height) * 0.68
            capa?.frame = b
            marco.frame = CGRect(x: (b.width - lado) / 2, y: (b.height - lado) / 2 - 30, width: lado, height: lado)
            texto.frame = CGRect(x: 20, y: marco.frame.minY - 70, width: b.width - 40, height: 60)
            if marco.isHidden { texto.frame = CGRect(x: 20, y: b.height / 2 - 90, width: b.width - 40, height: 80) }
            let abajo = b.height - view.safeAreaInsets.bottom - 70
            linterna.sizeToFit(); cancelar.sizeToFit()
            let lw = linterna.isHidden ? 0 : linterna.bounds.width, cw = cancelar.bounds.width, hueco: CGFloat = linterna.isHidden ? 0 : 14
            var x = (b.width - lw - cw - hueco) / 2
            if !linterna.isHidden { linterna.frame = CGRect(x: x, y: abajo, width: lw, height: 48); x += lw + hueco }
            cancelar.frame = CGRect(x: x, y: abajo, width: cw, height: 48)
        }

        @objc private func salir() { if sesion.isRunning { sesion.stopRunning() }; dismiss(animated: true) }
        @objc private func ajustes() { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
        @objc private func luz() {
            guard let d = disp, d.hasTorch, (try? d.lockForConfiguration()) != nil else { return }
            d.torchMode = d.torchMode == .on ? .off : .on
            d.unlockForConfiguration()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let d = disp, d.hasTorch, d.torchMode == .on, (try? d.lockForConfiguration()) != nil { d.torchMode = .off; d.unlockForConfiguration() }
            if sesion.isRunning { sesion.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objs: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hecho, let o = objs.first as? AVMetadataMachineReadableCodeObject, let s = o.stringValue else { return }
            hecho = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            sesion.stopRunning()
            leido?(s)
        }
    }
}
