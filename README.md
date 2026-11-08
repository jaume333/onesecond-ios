# One Second · app iOS

Versión para iPhone de la app One Second (One Second Rally, Rider 1000 y Ronda la Llana), en Swift / SwiftUI, desde iOS 15.
Habla con el mismo servidor que la app Android (`jaume333/rallygps-app`).

- El proyecto de Xcode se genera con XcodeGen a partir de `project.yml` (no hace falta Mac: lo hace GitHub Actions).
- Actions › «Compilar iOS» compila en cada cambio. La subida a TestFlight se añadirá cuando esté la clave de API de App Store Connect.

Funciones: selector de pruebas, vincular (QR, dirección pegada, enlace de la web, dorsal y teléfono), EMITIR / PARAR con el GPS
en segundo plano y cola sin cobertura, puntos de control (Rider 1000 y Ronda), avisos de incidencias y mensajes con la organización.
Pendiente: One Second Navigator y «ver mis tiempos».
