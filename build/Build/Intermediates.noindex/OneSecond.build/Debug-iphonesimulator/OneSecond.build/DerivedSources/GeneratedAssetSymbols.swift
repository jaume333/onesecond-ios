import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
extension ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
extension ImageResource {

    /// The "cronometro" asset catalog image resource.
    static let cronometro = ImageResource(name: "cronometro", bundle: resourceBundle)

    /// The "ic_bingo" asset catalog image resource.
    static let icBingo = ImageResource(name: "ic_bingo", bundle: resourceBundle)

    /// The "ic_cazatopo" asset catalog image resource.
    static let icCazatopo = ImageResource(name: "ic_cazatopo", bundle: resourceBundle)

    /// The "ic_holdemrun" asset catalog image resource.
    static let icHoldemrun = ImageResource(name: "ic_holdemrun", bundle: resourceBundle)

    /// The "ic_navigator" asset catalog image resource.
    static let icNavigator = ImageResource(name: "ic_navigator", bundle: resourceBundle)

    /// The "ic_pokerrun" asset catalog image resource.
    static let icPokerrun = ImageResource(name: "ic_pokerrun", bundle: resourceBundle)

    /// The "ic_rally" asset catalog image resource.
    static let icRally = ImageResource(name: "ic_rally", bundle: resourceBundle)

    /// The "ic_rally_classics" asset catalog image resource.
    static let icRallyClassics = ImageResource(name: "ic_rally_classics", bundle: resourceBundle)

    /// The "ic_rallypoker" asset catalog image resource.
    static let icRallypoker = ImageResource(name: "ic_rallypoker", bundle: resourceBundle)

    /// The "ic_rider" asset catalog image resource.
    static let icRider = ImageResource(name: "ic_rider", bundle: resourceBundle)

    /// The "ic_ronda" asset catalog image resource.
    static let icRonda = ImageResource(name: "ic_ronda", bundle: resourceBundle)

    /// The "ic_ruta66" asset catalog image resource.
    static let icRuta66 = ImageResource(name: "ic_ruta66", bundle: resourceBundle)

    /// The "logo_rally_classics" asset catalog image resource.
    static let logoRallyClassics = ImageResource(name: "logo_rally_classics", bundle: resourceBundle)

    /// The "logo_rider_app" asset catalog image resource.
    static let logoRiderApp = ImageResource(name: "logo_rider_app", bundle: resourceBundle)

    /// The "logo_ronda" asset catalog image resource.
    static let logoRonda = ImageResource(name: "logo_ronda", bundle: resourceBundle)

    /// The "logo_ros" asset catalog image resource.
    static let logoRos = ImageResource(name: "logo_ros", bundle: resourceBundle)

    /// The "logo_ros_aro" asset catalog image resource.
    static let logoRosAro = ImageResource(name: "logo_ros_aro", bundle: resourceBundle)

    /// The "nav_estilo_3d" asset catalog image resource.
    static let navEstilo3D = ImageResource(name: "nav_estilo_3d", bundle: resourceBundle)

    /// The "nav_estilo_claro" asset catalog image resource.
    static let navEstiloClaro = ImageResource(name: "nav_estilo_claro", bundle: resourceBundle)

    /// The "nav_estilo_fp" asset catalog image resource.
    static let navEstiloFp = ImageResource(name: "nav_estilo_fp", bundle: resourceBundle)

    /// The "nav_estilo_hibrido" asset catalog image resource.
    static let navEstiloHibrido = ImageResource(name: "nav_estilo_hibrido", bundle: resourceBundle)

    /// The "nav_estilo_oscuro" asset catalog image resource.
    static let navEstiloOscuro = ImageResource(name: "nav_estilo_oscuro", bundle: resourceBundle)

    /// The "nav_estilo_relieve" asset catalog image resource.
    static let navEstiloRelieve = ImageResource(name: "nav_estilo_relieve", bundle: resourceBundle)

    /// The "nav_estilo_satelite" asset catalog image resource.
    static let navEstiloSatelite = ImageResource(name: "nav_estilo_satelite", bundle: resourceBundle)

    /// The "nav_estilo_topo" asset catalog image resource.
    static let navEstiloTopo = ImageResource(name: "nav_estilo_topo", bundle: resourceBundle)

}

// MARK: - Backwards Deployment Support -

/// A color resource.
struct ColorResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog color resource name.
    fileprivate let name: Swift.String

    /// An asset catalog color resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize a `ColorResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

/// An image resource.
struct ImageResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog image resource name.
    fileprivate let name: Swift.String

    /// An asset catalog image resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize an `ImageResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// Initialize a `NSColor` with a color resource.
    convenience init(resource: ColorResource) {
        self.init(named: NSColor.Name(resource.name), bundle: resource.bundle)!
    }

}

protocol _ACResourceInitProtocol {}
extension AppKit.NSImage: _ACResourceInitProtocol {}

@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension _ACResourceInitProtocol {

    /// Initialize a `NSImage` with an image resource.
    init(resource: ImageResource) {
        self = resource.bundle.image(forResource: NSImage.Name(resource.name))! as! Self
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// Initialize a `UIColor` with a color resource.
    convenience init(resource: ColorResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}

@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// Initialize a `UIImage` with an image resource.
    convenience init(resource: ImageResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    /// Initialize a `Color` with a color resource.
    init(_ resource: ColorResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Image {

    /// Initialize an `Image` with an image resource.
    init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}
#endif