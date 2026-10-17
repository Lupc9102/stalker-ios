import AppKit
import Darwin

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}
guard CommandLine.arguments.count == 2,
      let image = NSBitmapImageRep(contentsOfFile: CommandLine.arguments[1]),
      image.pixelsWide > 0, image.pixelsHigh > 0 else { fail("Cannot read simulator screenshot") }
var colorful = 0, sampled = 0
for y in stride(from: 0, to: image.pixelsHigh, by: 8) {
    for x in stride(from: 0, to: image.pixelsWide, by: 8) {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let high = max(max(color.redComponent, color.greenComponent), color.blueComponent)
        let low = min(min(color.redComponent, color.greenComponent), color.blueComponent)
        if high > 0.05 && high - low > 0.04 { colorful += 1 }; sampled += 1
    }
}
guard sampled > 0, colorful > sampled / 100 else {
    fail("Simulator screen is blank/monochrome: \(colorful) colored pixels out of \(sampled) samples")
}
print("Simulator screen verified: \(colorful) colored pixels out of \(sampled) samples")
