// Draws Narrate's app icon (a white speech bubble on a purple rounded square)
// and saves it as a 1024×1024 PNG. build.sh runs this when icon.png is missing:
//   swift makeicon.swift icon.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
else { fatalError("Couldn't create the icon canvas") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// AppKit's origin is bottom-left, so y values are measured from the bottom.
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(deviceRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

// Rounded square with a top-to-bottom indigo → violet gradient
let square = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                          xRadius: 185, yRadius: 185)
NSGradient(starting: rgb(88, 86, 214), ending: rgb(175, 82, 222))!
    .draw(in: square, angle: -90)

// Speech bubble with a tail at the bottom-left
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 250, y: 1024 - 665, width: 524, height: 380),
             xRadius: 95, yRadius: 95).fill()
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 345, y: 1024 - 640))
tail.line(to: NSPoint(x: 330, y: 1024 - 775))
tail.line(to: NSPoint(x: 470, y: 1024 - 655))
tail.close()
tail.fill()

// Three "text" lines inside the bubble
rgb(98, 84, 216).setFill()
for (i, right) in [690, 690, 560].enumerated() {
    let top = 372 + i * 95
    NSBezierPath(roundedRect: NSRect(x: 334, y: 1024 - top - 44, width: right - 334, height: 44),
                 xRadius: 22, yRadius: 22).fill()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Couldn't encode the icon")
}
try! png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
