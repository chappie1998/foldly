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
                let value: UInt8 = (x / 4).isMultiple(of: 2) ? 32 : 224
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
        check(contrast(early, y: top) < contrast(early, y: bottom) * 0.35, "early fold must blur the top more than the bottom")
        check(abs(contrast(early, y: bottom) - contrast(original, y: bottom)) < 2, "bottom stays sharp during the initial fold")
        check(abs(contrast(early, y: center) - contrast(original, y: center)) < 2, "middle stays sharp during the initial fold")
        check(contrast(middle, y: center) < contrast(early, y: center) * 0.7, "blur must progress down into the middle")
        check(contrast(deep, y: bottom) < contrast(early, y: bottom) * 0.8, "lower screen starts to soften only late in the fold")
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
        // Variable blur's sampling grid can shift a few 8-bit contrast levels
        // with the origin; the blur boundary itself must stay in place.
        check(profileDifference < 3, "gradient must follow translated image coordinates")
        print("PASS: top-first blur, initially sharp bottom, gradual downward progression, opaque borders, and offset images")
        print("Contrast early top/middle/bottom: \(contrast(early, y: top))/\(contrast(early, y: center))/\(contrast(early, y: bottom))")
        print("Contrast middle center: \(contrast(middle, y: center)); deep bottom: \(contrast(deep, y: bottom))")
    }
}
