import CoreImage
import Foundation

@main enum GradientBlurTests {
    static func main() {
        let width = 640, height = 400
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let context = CIContext()
        var stripes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                // Eight-pixel stripes retain measurable contrast under light
                // blur, so the lower screen can be compared with the strong top.
                let value: UInt8 = (x / 8).isMultiple(of: 2) ? 32 : 224
                let index = (y * width + x) * 4
                stripes[index] = value
                stripes[index + 1] = value
                stripes[index + 2] = value
            }
        }
        let source = CIImage(bitmapData: Data(stripes), bytesPerRow: width * 4,
                             size: bounds.size, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        func pixels(_ image: CIImage) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: stripes.count)
            result.withUnsafeMutableBytes { bytes in
                context.render(image, toBitmap: bytes.baseAddress!, rowBytes: width * 4,
                               bounds: bounds, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            }
            return result
        }
        func contrast(_ image: [UInt8], y: Int) -> Double {
            let row = (32..<(width - 32)).map { Double(image[(y * width + $0) * 4]) }
            let mean = row.reduce(0, +) / Double(row.count)
            return sqrt(row.reduce(0) { $0 + pow($1 - mean, 2) } / Double(row.count))
        }
        func check(_ valid: Bool, _ message: String) {
            guard valid else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let original = pixels(source)
        let early = pixels(BendRenderer.blur(source, radius: 8, closure: 0.15))
        let middle = pixels(BendRenderer.blur(source, radius: 14, closure: 0.5))
        let deep = pixels(BendRenderer.blur(source, radius: 24, closure: 0.9))
        // CIContext's bitmap rows are top-first, unlike the filter's y-up
        // coordinates. Sample visible top and bottom in that output order.
        let bottom = 360, center = 200, top = 20
        print("Contrast middle top/center/bottom/hinge: \(contrast(middle, y: top))/\(contrast(middle, y: center))/\(contrast(middle, y: bottom))/\(contrast(middle, y: 392)); deep bottom: \(contrast(deep, y: bottom))")
        check(contrast(early, y: top) < contrast(early, y: bottom) * 0.35, "early fold must blur the top more than the bottom")
        check(abs(contrast(early, y: bottom) - contrast(original, y: bottom)) < 2, "bottom stays sharp during the initial fold")
        check(abs(contrast(early, y: center) - contrast(original, y: center)) < 2, "middle stays sharp during the initial fold")
        check(contrast(middle, y: center) < contrast(early, y: center) * 0.7, "blur must progress down into the middle")
        check(contrast(middle, y: bottom) < contrast(original, y: bottom) * 0.85, "bottom must already soften halfway through the fold")
        check(contrast(middle, y: 392) < contrast(original, y: 392) * 0.95, "light blur must reach the hinge by halfway closed")
        check(contrast(middle, y: bottom) > contrast(middle, y: top) + 15, "halfway bottom blur must stay lighter than the top")
        check(contrast(deep, y: bottom) < contrast(middle, y: bottom) * 0.8, "bottom blur must strengthen as the fold deepens")
        check(pixels(BendRenderer.blur(source, radius: 0, closure: 0.5)) == original, "zero radius preserves the image")
        check(pixels(BendRenderer.blur(source, radius: 20, closure: 0)) == original, "fully open preserves the image")
        for rendered in [early, middle, deep] {
            check(stride(from: 3, to: rendered.count, by: 4).allSatisfy { rendered[$0] == 255 }, "variable blur must not expose transparent borders")
        }
        // Core Image coordinates can have a nonzero origin. The blur mask must
        // follow the source image rather than the absolute display coordinate.
        let offset = CGAffineTransform(translationX: 91, y: 57)
        let translated = BendRenderer.blur(source.transformed(by: offset), radius: 8, closure: 0.15)
            .transformed(by: offset.inverted())
        let shifted = pixels(translated)
        let profileDifference = stride(from: 20, through: 380, by: 20).map {
            abs(contrast(shifted, y: $0) - contrast(early, y: $0))
        }.max()!
        print("Maximum translated contrast difference: \(profileDifference)")
        // Variable blur's sampling grid shifts with the origin. Allow at most
        // 5% of the source contrast while requiring the blur profile to follow.
        check(profileDifference < contrast(original, y: center) * 0.05, "gradient must follow translated image coordinates")
        print("PASS: top-first blur, initially sharp bottom, gradual downward progression, opaque borders, and offset images")
        print("Contrast early top/middle/bottom: \(contrast(early, y: top))/\(contrast(early, y: center))/\(contrast(early, y: bottom))")
    }
}
