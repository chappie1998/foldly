import CoreImage
import Foundation

enum BendyStyle: String, CaseIterable, Identifiable { case silk = "Silk", shade = "Shade", frost = "Frost"; var id: String { rawValue } }

struct BendParameters { var angle: Double; var clearAngle: Double = 105; var perspective: Double; var blur: Double; var shadow: Double; var style: BendyStyle }

struct BendGeometry {
    let openness: CGFloat; let topExpansion: CGFloat; let outputHeight: CGFloat
    static func calculate(size: CGSize, parameters: BendParameters) -> BendGeometry {
        let openness = CGFloat(min(1, max(0, (parameters.angle - 15) / max(1, parameters.clearAngle - 15))))
        let closure = 1 - openness
        // Match the website's desktop-surface tilt, not its outer laptop lid.
        // The physical lid already rotates in the user's hands. Perspective
        // brings the top edge toward the viewer, beyond the display's crop.
        let rotation = closure * 12.075 * CGFloat(min(1, max(0.25, parameters.perspective))) * .pi / 180
        let projection = 1 / (1 - 0.5 * sin(rotation))
        return .init(openness: openness,
                     topExpansion: size.width * (projection - 1) / 2,
                     outputHeight: size.height * cos(rotation) * projection)
    }
}

struct FoldBlurProfile {
    // Coordinates run from the hinge (0) to the top of the display (1).
    // The clear region retreats beyond the hinge before halfway closed,
    // giving the bottom a light blur while the top remains much stronger.
    let clearUntil: Double
    let fullFrom: Double

    init(closure: Double) {
        let progress = min(1, max(0, closure))
        clearUntil = 0.82 - 2.0 * progress
        fullFrom = 0.97 - 0.36 * progress
    }

    func strength(at height: Double) -> Double {
        let t = min(1, max(0, (height - clearUntil) / (fullFrom - clearUntil)))
        return t * t * (3 - 2 * t)
    }

    func mask(in extent: CGRect) -> CIImage {
        CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": CIVector(x: extent.midX, y: extent.minY + extent.height * clearUntil),
            "inputPoint1": CIVector(x: extent.midX, y: extent.minY + extent.height * fullFrom),
            "inputColor0": CIColor.black,
            "inputColor1": CIColor.white
        ])!.outputImage!.cropped(to: extent)
    }
}

enum BendRenderer {
    static func blur(_ source: CIImage, radius: Double, closure: Double) -> CIImage {
        guard radius > 0.01, closure > 0 else { return source }
        let extent = source.extent
        let mask = FoldBlurProfile(closure: closure).mask(in: extent)
        return source.clampedToExtent().applyingFilter("CIMaskedVariableBlur", parameters: [
            "inputMask": mask, kCIInputRadiusKey: radius
        ]).cropped(to: extent)
    }

    static func image(_ source: CIImage, parameters: BendParameters) -> CIImage {
        let extent = source.extent.integral
        guard extent.width > 0, extent.height > 0 else { return source }
        let geometry = BendGeometry.calculate(size: extent.size, parameters: parameters)
        let closure = Double(1 - geometry.openness)
        guard closure > 0.0001 else { return source }
        let style: (Double, Double, Double) = parameters.style == .frost ? (3.0, 0.84, 0.96) : parameters.style == .shade ? (0, 0.78, 0.84) : (0.25, 1.05, 1.04)
        let radius = max(0, (parameters.blur * (parameters.style == .frost ? 17 : 8) + style.0) * closure * extent.height / 600)
        var prepared = blur(source, radius: radius, closure: closure)
        prepared = prepared.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + (style.1 - 1) * closure, kCIInputContrastKey: 1 + (style.2 - 1) * closure])
        let frost = parameters.style == .frost
        let wash = frost ? closure * 0.14 : 0
        let dim = max(0.3, 1 - closure * ((frost ? 0.10 : 0.24) + (parameters.style == .shade ? 0.18 : 0) + parameters.shadow * (frost ? 0.12 : 0.24))) * (1 - wash)
        prepared = prepared.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: dim, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: dim, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: dim, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: wash * 0.94, y: wash * 0.94, z: wash * 0.98, w: 0)])
        let folded = prepared.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputBottomLeft": CIVector(x: extent.minX, y: extent.minY),
            "inputBottomRight": CIVector(x: extent.maxX, y: extent.minY),
            "inputTopLeft": CIVector(x: extent.minX - geometry.topExpansion, y: extent.minY + geometry.outputHeight),
            "inputTopRight": CIVector(x: extent.maxX + geometry.topExpansion, y: extent.minY + geometry.outputHeight)])
        // Clip inside the physical display, as the website's screen-well does.
        // Back subpixel sampling at the hinge with the same treated desktop.
        return folded.cropped(to: extent).composited(over: prepared).cropped(to: extent)
    }
}

enum BendySelfTest {
    static func run() -> Bool {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400), source = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 400))
        let context = CIContext()
        let testParameters = { (angle: Double) in BendParameters(angle: angle, perspective: 0.75, blur: 0.4, shadow: 0.6, style: .silk) }
        let open = BendGeometry.calculate(size: bounds.size, parameters: testParameters(105))
        guard open.openness == 1, open.topExpansion == 0, open.outputHeight == bounds.height,
              BendRenderer.image(source, parameters: testParameters(105)).extent == source.extent else {
            fputs("Geometry self-test failed: open state is not identity\n", stderr); return false
        }
        for angle in [15.0, 60.0, 105.0] {
            let geometry = BendGeometry.calculate(size: bounds.size, parameters: testParameters(angle))
            let topWidth = bounds.width + 2 * geometry.topExpansion, bottomWidth = bounds.width
            guard geometry.openness.isFinite, geometry.topExpansion.isFinite, geometry.outputHeight.isFinite,
                  geometry.topExpansion >= 0, bottomWidth > 0, bottomWidth <= topWidth,
                  geometry.outputHeight >= bounds.height, geometry.outputHeight < bounds.height * 1.2,
                  angle == 105 || topWidth > bottomWidth else {
                fputs("Geometry self-test failed at \(Int(angle))°\n", stderr); return false
            }
        }
        for style in BendyStyle.allCases { for angle in [15.0, 60.0, 105.0] {
            let p = BendParameters(angle: angle, perspective: 0.75, blur: 0.4, shadow: 0.6, style: style), output = BendRenderer.image(source, parameters: p)
            guard output.extent == bounds, context.createCGImage(output, from: output.extent.integral) != nil else {
                fputs("Render self-test failed: \(style.rawValue) at \(Int(angle))°, extent \(output.extent)\n", stderr)
                return false
            }
            var pixels = [UInt8](repeating: 0, count: 640 * 400 * 4)
            pixels.withUnsafeMutableBytes { bytes in
                context.render(output, toBitmap: bytes.baseAddress!, rowBytes: 640 * 4,
                               bounds: bounds, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            }
            for i in stride(from: 0, to: pixels.count, by: 4) {
                guard min(pixels[i], pixels[i + 1], pixels[i + 2]) > 32, pixels[i + 3] == 255 else {
                    fputs("Coverage self-test failed: exposed canvas in \(style.rawValue) at \(Int(angle))°\n", stderr)
                    return false
                }
            }
        }}
        print("Foldly render self-test passed (3 styles × 3 angles)."); return true
    }
}

// Keep a single capture session across lid movement while Foldly is enabled.
struct CaptureGate {
    private(set) var isActive = false
    enum Action { case start, stop, none }
    mutating func update(angle: Double, allowed: Bool) -> Action {
        let wanted = allowed && angle.isFinite
        guard wanted != isActive else { return .none }
        isActive = wanted
        return wanted ? .start : .stop
    }
}

struct FoldMotion {
    var angle: Double
    mutating func advance(toward target: Double, deltaTime: Double, reduceMotion: Bool = false) -> Double {
        guard target.isFinite else { return angle }
        if reduceMotion { angle = target; return angle }
        let dt = min(0.05, max(0, deltaTime))
        angle += (target - angle) * (1 - exp(-dt / 0.10))
        if abs(target - angle) < 0.03 { angle = target }
        return angle
    }
}
