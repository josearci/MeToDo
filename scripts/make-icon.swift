import AppKit

// make-icon SOURCE OUT.png — crop the dark rounded-square icon out of a light mockup and
// lay it on a 1024² transparent canvas the way macOS icons are drawn (824² body + shadow).
let args = CommandLine.arguments
let src = NSImage(contentsOfFile: args[1])!
var rect = CGRect(origin: .zero, size: src.size)
let cg = src.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let w = cg.width, h = cg.height

// Bitmap access
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
func dark(_ x: Int, _ y: Int) -> Bool {   // y from top
    let i = ((h - 1 - y) * w + x) * 4
    return (Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2])) / 3 < 110
}

// Bounding box of the dark body: scan the middle row and column (corners are rounded).
var minX = w, maxX = 0, minY = h, maxY = 0
let midY = h / 2, midX = w / 2
for x in 0..<w where dark(x, midY) { minX = min(minX, x); maxX = max(maxX, x) }
for y in 0..<h where dark(midX, y) { minY = min(minY, y); maxY = max(maxY, y) }
// Corner radius: along the top edge, how far in from the left the first dark pixel sits.
var radiusScan = 0
for x in minX..<maxX where dark(x, minY + 1) { radiusScan = x - minX; break }
print("body x \(minX)...\(maxX) y \(minY)...\(maxY), top-edge inset \(radiusScan)")

let side = min(maxX - minX, maxY - minY)
let inset = 3   // trim the anti-aliased rim so no light background bleeds in
let crop = cg.cropping(to: CGRect(x: minX + inset, y: minY + inset, width: side - 2 * inset, height: side - 2 * inset))!

// Draw onto 1024² canvas: 824² body centered slightly high, continuous-corner clip, soft shadow.
let canvas = 1024, body: CGFloat = 824
let out = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: canvas * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let bodyRect = CGRect(x: (CGFloat(canvas) - body) / 2, y: (CGFloat(canvas) - body) / 2 + 10, width: body, height: body)
let radius = body * 0.2237   // Apple's macOS icon corner ratio
let path = CGPath(roundedRect: bodyRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

out.saveGState()
out.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
out.addPath(path); out.setFillColor(NSColor.black.cgColor); out.fillPath()
out.restoreGState()

out.saveGState()
out.addPath(path); out.clip()
out.interpolationQuality = .high
// Scale the source body so its own rounded corners fall outside our clip.
let overscan: CGFloat = 1.06
let drawRect = bodyRect.insetBy(dx: -body * (overscan - 1) / 2, dy: -body * (overscan - 1) / 2)
out.draw(crop, in: drawRect)
out.restoreGState()

let rep = NSBitmapImageRep(cgImage: out.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
