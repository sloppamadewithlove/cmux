import SwiftUI
import CoreGraphics

/// Procedurally generated multi-arm rainbow spiral, rendered into a CGImage exactly once
/// per process and then cached for cheap reuse. Display via `RainbowSpiralImage.shared`
/// inside an Image with `.rotationEffect` for animation.
///
/// The pattern itself is static — it is the rotation of the entire image that produces
/// the "spiral movement" the user wants. Rendering once and rotating is dramatically
/// cheaper than redrawing per frame, and yields identical visuals because the pattern
/// has rotational structure (rotating a perfect spiral by Δθ looks like the spiral
/// "spinning" without internal change).
enum RainbowSpiralImage {
    /// Side length in pixels of the cached CGImage. Large enough that scaling up to fill
    /// any reasonable pane stays smooth; small enough that the one-shot pixel fill is
    /// well under a frame at app launch.
    private static let size: Int = 768

    /// Number of color arms in the spiral. The reference image has ~6 visible arms.
    private static let arms: Double = 6

    /// Twist coefficient: how much the hue rotates per pixel of radius. Larger = tighter
    /// spiral. Tuned so a 768px image shows ~3 full hue rotations from center to edge,
    /// matching the reference.
    private static let twist: Double = 0.018

    static let shared: CGImage? = render()

    private static func render() -> CGImage? {
        let width = size
        let height = size
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let cx = Double(width) / 2.0
        let cy = Double(height) / 2.0
        let maxR = sqrt(cx * cx + cy * cy)

        for y in 0..<height {
            let dy = Double(y) - cy
            for x in 0..<width {
                let dx = Double(x) - cx
                let r = sqrt(dx * dx + dy * dy)
                var theta = atan2(dy, dx)
                if theta < 0 { theta += 2.0 * .pi }

                // Spiral hue: arms wrap around θ, then twist with radius.
                let raw = (theta * arms / (2.0 * .pi)) - (r * twist)
                var hue = raw.truncatingRemainder(dividingBy: 1.0)
                if hue < 0 { hue += 1.0 }

                // Brightness tapers slightly toward the edge so the center reads as the
                // bright convergence point in the reference image. Saturation stays full.
                let edgeFalloff = 1.0 - 0.15 * (r / maxR)
                let (red, green, blue) = hsbToRGB(hue: hue, saturation: 1.0, brightness: edgeFalloff)

                let i = (y * width + x) * bytesPerPixel
                pixels[i + 0] = UInt8(red * 255.0)
                pixels[i + 1] = UInt8(green * 255.0)
                pixels[i + 2] = UInt8(blue * 255.0)
                pixels[i + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            CGBitmapInfo(rawValue: CGImageByteOrderInfo.order32Big.rawValue)
        ]

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Standard HSB → RGB conversion. Inputs in [0, 1], outputs in [0, 1].
    private static func hsbToRGB(hue: Double, saturation: Double, brightness: Double) -> (Double, Double, Double) {
        if saturation == 0 {
            return (brightness, brightness, brightness)
        }
        let h = hue * 6.0
        let sector = floor(h)
        let f = h - sector
        let p = brightness * (1.0 - saturation)
        let q = brightness * (1.0 - saturation * f)
        let t = brightness * (1.0 - saturation * (1.0 - f))
        switch Int(sector) % 6 {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }
}
