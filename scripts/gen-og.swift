// Генератор og.png 1280×640 для соцсетей-превью: графитовый градиент,
// глиф «три пилюли-гейджа» (эхо иконки), wordmark + слоган из hero лендинга.
// Шрифты системные (SF + системный serif italic) — Inter/Instrument Serif
// с Google Fonts в CoreGraphics недоступны, SF визуально совместим.
// Запуск: swift scripts/gen-og.swift → site/assets/og.png
import AppKit
import CoreGraphics

let W: CGFloat = 1280, H: CGFloat = 640
// Явный bitmap 1280×640: lockFocus() на retina-экране рисует в 2x.
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Фон: тот же графитовый градиент, что на тайле иконки, но во весь кадр.
let top = NSColor(srgbRed: 0.145, green: 0.145, blue: 0.165, alpha: 1)
let bottom = NSColor(srgbRed: 0.086, green: 0.086, blue: 0.102, alpha: 1)
NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// Глиф: три бара как в иконке, слева от wordmark, по центру композиции.
struct Bar { let fill: CGFloat; let color: NSColor }
let bars: [Bar] = [
    Bar(fill: 0.78, color: NSColor(srgbRed: 0.92, green: 0.91, blue: 0.89, alpha: 1)),
    Bar(fill: 0.52, color: NSColor(srgbRed: 0.92, green: 0.91, blue: 0.89, alpha: 1)),
    Bar(fill: 0.24, color: NSColor(srgbRed: 1.00, green: 0.69, blue: 0.25, alpha: 1)),
]
let barW: CGFloat = 34, gap: CGFloat = 24, trackH: CGFloat = 190
let glyphW = barW * 3 + gap * 2

// Метрики текста — чтобы центрировать связку «глиф + wordmark» целиком.
let wordFont = NSFont.systemFont(ofSize: 96, weight: .semibold)
let wordAttrs: [NSAttributedString.Key: Any] = [
    .font: wordFont,
    .foregroundColor: NSColor(srgbRed: 0.95, green: 0.94, blue: 0.93, alpha: 1),
    .kern: -1.5,
]
let word = NSAttributedString(string: "LimitBar", attributes: wordAttrs)
let wordSize = word.size()

let glyphGap: CGFloat = 56
let rowW = glyphW + glyphGap + wordSize.width
let rowX = (W - rowW) / 2
let rowCenterY: CGFloat = H * 0.58

// Бары (выравнены по вертикальному центру строки)
let barsY = rowCenterY - trackH / 2
for (i, bar) in bars.enumerated() {
    let x = rowX + CGFloat(i) * (barW + gap)
    let track = NSBezierPath(roundedRect: NSRect(x: x, y: barsY, width: barW, height: trackH),
                             xRadius: barW / 2, yRadius: barW / 2)
    NSColor(white: 1, alpha: 0.10).setFill()
    track.fill()
    let h = max(barW, trackH * bar.fill)
    let fill = NSBezierPath(roundedRect: NSRect(x: x, y: barsY, width: barW, height: h),
                            xRadius: barW / 2, yRadius: barW / 2)
    bar.color.setFill()
    fill.fill()
}

// Wordmark
word.draw(at: NSPoint(x: rowX + glyphW + glyphGap, y: rowCenterY - wordSize.height / 2))

// Слоган из hero: обычная часть SF, «always in sight.» — serif italic + янтарь.
let tagSize: CGFloat = 40
let tagPlain: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: tagSize, weight: .regular),
    .foregroundColor: NSColor(white: 1, alpha: 0.62),
]
var serif = NSFont.systemFont(ofSize: tagSize, weight: .regular)
if let d = serif.fontDescriptor.withDesign(.serif),
   let f = NSFont(descriptor: d.withSymbolicTraits(.italic), size: tagSize) {
    serif = f
}
let tagAccent: [NSAttributedString.Key: Any] = [
    .font: serif,
    .foregroundColor: NSColor(srgbRed: 1.00, green: 0.69, blue: 0.25, alpha: 1),
]
let tagline = NSMutableAttributedString(string: "Your AI limits, ", attributes: tagPlain)
tagline.append(NSAttributedString(string: "always in sight.", attributes: tagAccent))
let tagWidth = tagline.size().width
tagline.draw(at: NSPoint(x: (W - tagWidth) / 2, y: rowCenterY - trackH / 2 - 96))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png fail") }
let out = URL(fileURLWithPath: "site/assets/og.png")
try! png.write(to: out)
print("written: \(out.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
