import CoreImage
import Foundation

enum BendyStyle: String, CaseIterable, Identifiable { case silk = "Silk", shade = "Shade", frost = "Frost"; var id: String { rawValue } }

struct BendParameters { var angle: Double; var clearAngle: Double = 107; var perspective: Double; var blur: Double; var shadow: Double; var style: BendyStyle }

struct BendGeometry {
    let openness: CGFloat; let bottomInset: CGFloat; let outputHeight: CGFloat
    static func calculate(size: CGSize, parameters: BendParameters) -> BendGeometry {
        let openness = CGFloat(min(1, max(0, (parameters.angle - 15) / max(1, parameters.clearAngle - 15))))
        let closure = 1 - openness
        let rotation = closure * 74 * .pi / 180
        return .init(openness: openness,
                     bottomInset: size.width * sin(rotation) * CGFloat(min(1, max(0, parameters.perspective))) * 0.065,
                     outputHeight: size.height * cos(rotation))
    }
}

enum BendRenderer {
    static func image(_ source: CIImage, parameters: BendParameters) -> CIImage {
        let extent = source.extent.integral
        guard extent.width > 0, extent.height > 0 else { return source }
        let geometry = BendGeometry.calculate(size: extent.size, parameters: parameters)
        let closure = Double(1 - geometry.openness)
        guard closure > 0.0001 else { return source }
        let style: (Double, Double, Double) = parameters.style == .frost ? (3.0, 0.84, 0.96) : parameters.style == .shade ? (0, 0.78, 0.84) : (0.25, 1.05, 1.04)
        var prepared = source
        let radius = max(0, (parameters.blur * (parameters.style == .frost ? 17 : 8) + style.0) * closure * extent.height / 600)
        if radius > 0.01 { prepared = prepared.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: extent) }
        prepared = prepared.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 + (style.1 - 1) * closure, kCIInputContrastKey: 1 + (style.2 - 1) * closure])
        let frost = parameters.style == .frost
        let wash = frost ? closure * 0.14 : 0
        let dim = max(0.3, 1 - closure * ((frost ? 0.10 : 0.24) + (parameters.style == .shade ? 0.18 : 0) + parameters.shadow * (frost ? 0.12 : 0.24))) * (1 - wash)
        prepared = prepared.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: dim, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: dim, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: dim, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: wash * 0.94, y: wash * 0.94, z: wash * 0.98, w: 0)])
        let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: extent), "inputRadius": extent.height * 0.025 * closure,
            "inputColor": CIColor.white])!.outputImage!.cropped(to: extent)
        prepared = prepared.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent), "inputMaskImage": mask])
        let folded = prepared.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputBottomLeft": CIVector(x: extent.minX + geometry.bottomInset, y: extent.minY),
            "inputBottomRight": CIVector(x: extent.maxX - geometry.bottomInset, y: extent.minY),
            "inputTopLeft": CIVector(x: extent.minX, y: extent.minY + geometry.outputHeight),
            "inputTopRight": CIVector(x: extent.maxX, y: extent.minY + geometry.outputHeight)])
        // Feather the projected silhouette, including its moving top edge.
        return folded.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: extent.height * 0.002 * closure]).cropped(to: extent)
    }
}

enum BendySelfTest {
    static func run() -> Bool {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400), source = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 400))
        let context = CIContext()
        let testParameters = { (angle: Double) in BendParameters(angle: angle, perspective: 0.75, blur: 0.4, shadow: 0.6, style: .silk) }
        let open = BendGeometry.calculate(size: bounds.size, parameters: testParameters(107))
        guard open.openness == 1, open.bottomInset == 0, open.outputHeight == bounds.height,
              BendRenderer.image(source, parameters: testParameters(107)).extent == source.extent else {
            fputs("Geometry self-test failed: open state is not identity\n", stderr); return false
        }
        for angle in [15.0, 60.0, 107.0] {
            let geometry = BendGeometry.calculate(size: bounds.size, parameters: testParameters(angle))
            let topWidth = bounds.width, bottomWidth = bounds.width - 2 * geometry.bottomInset
            guard geometry.openness.isFinite, geometry.bottomInset.isFinite, geometry.outputHeight.isFinite,
                  geometry.bottomInset >= 0, bottomWidth > 0, bottomWidth <= topWidth,
                  geometry.outputHeight > 0, geometry.outputHeight <= bounds.height,
                  angle == 107 || topWidth > bottomWidth else {
                fputs("Geometry self-test failed at \(Int(angle))°\n", stderr); return false
            }
        }
        for style in BendyStyle.allCases { for angle in [15.0, 60.0, 107.0] {
            let p = BendParameters(angle: angle, perspective: 0.75, blur: 0.4, shadow: 0.6, style: style), output = BendRenderer.image(source, parameters: p)
            guard output.extent.width.isFinite, output.extent.height.isFinite, context.createCGImage(output, from: output.extent.integral) != nil else {
                fputs("Render self-test failed: \(style.rawValue) at \(Int(angle))°, extent \(output.extent)\n", stderr)
                return false
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
