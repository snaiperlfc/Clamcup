// Рисует иконку Clamcup: закрытый ноутбук, на нём кружка с паром.
// SF Symbols в иконках приложений использовать нельзя, поэтому всё нарисовано вручную.
//
//   swift scripts/make-icon.swift <out.png>   — 1024×1024
// Набор размеров и .icns собирает scripts/make-icon.sh.

import AppKit

let size: CGFloat = 1024
let outPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func fill(_ path: NSBezierPath, top: NSColor, bottom: NSColor) {
    NSGradient(starting: bottom, ending: top)?.draw(in: path, angle: 90)
}

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

// Подложка по сетке иконок macOS: 824×824 с отступом 100 и мягкой тенью
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
color(0x172B45).setFill()
platePath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
platePath.addClip()
fill(platePath, top: color(0x2A4C74), bottom: color(0x0F1D31))

// Лёгкий блик сверху
let sheen = NSBezierPath(rect: NSRect(x: 100, y: 512, width: 824, height: 412))
NSGradient(starting: color(0xFFFFFF, 0), ending: color(0xFFFFFF, 0.07))?.draw(in: sheen, angle: 90)
NSGraphicsContext.restoreGraphicsState()

// Закрытый ноутбук в лёгкой перспективе: крышка трапецией, под ней торец корпуса
let frontY: CGFloat = 262
let backY: CGFloat = 392
let edge: CGFloat = 30
let lidPath = NSBezierPath()
lidPath.move(to: NSPoint(x: 178, y: frontY))
lidPath.line(to: NSPoint(x: 846, y: frontY))
lidPath.line(to: NSPoint(x: 762, y: backY))
lidPath.line(to: NSPoint(x: 262, y: backY))
lidPath.close()
lidPath.lineJoinStyle = .round

let front = NSBezierPath(roundedRect: NSRect(x: 178, y: frontY - edge, width: 668, height: edge + 6), xRadius: 12, yRadius: 12)
fill(front, top: color(0x9AA3B1), bottom: color(0x6E7889))
fill(lidPath, top: color(0xC9D0DA), bottom: color(0xEEF1F5))
// Выемка под палец на переднем крае
let notch = NSBezierPath(roundedRect: NSRect(x: 462, y: frontY - 12, width: 100, height: 12), xRadius: 6, yRadius: 6)
color(0x5E6878).setFill()
notch.fill()

// Кружка стоит на крышке
let mugBottom = frontY + 40

// Тень кружки на крышке
let mugShadow = NSBezierPath(ovalIn: NSRect(x: 318, y: mugBottom - 16, width: 330, height: 40))
color(0x000000, 0.18).setFill()
mugShadow.fill()
let mugLeft: CGFloat = 330
let mugWidth: CGFloat = 290
let mugHeight: CGFloat = 270
let mugTop = mugBottom + mugHeight

// Ручка: кольцо справа, рисуется под корпусом
let handle = NSBezierPath(ovalIn: NSRect(x: mugLeft + mugWidth - 70, y: mugBottom + 70, width: 160, height: 150))
handle.lineWidth = 36
color(0xDCCFBE).setStroke()
handle.stroke()

let body = NSBezierPath()
let bottomRadius: CGFloat = 80
let topRadius: CGFloat = 16
body.move(to: NSPoint(x: mugLeft + topRadius, y: mugTop))
body.line(to: NSPoint(x: mugLeft + mugWidth - topRadius, y: mugTop))
body.curve(
    to: NSPoint(x: mugLeft + mugWidth, y: mugTop - topRadius),
    controlPoint1: NSPoint(x: mugLeft + mugWidth - topRadius / 2, y: mugTop),
    controlPoint2: NSPoint(x: mugLeft + mugWidth, y: mugTop - topRadius / 2)
)
body.line(to: NSPoint(x: mugLeft + mugWidth, y: mugBottom + bottomRadius))
body.curve(
    to: NSPoint(x: mugLeft + mugWidth - bottomRadius, y: mugBottom),
    controlPoint1: NSPoint(x: mugLeft + mugWidth, y: mugBottom + bottomRadius * 0.45),
    controlPoint2: NSPoint(x: mugLeft + mugWidth - bottomRadius * 0.45, y: mugBottom)
)
body.line(to: NSPoint(x: mugLeft + bottomRadius, y: mugBottom))
body.curve(
    to: NSPoint(x: mugLeft, y: mugBottom + bottomRadius),
    controlPoint1: NSPoint(x: mugLeft + bottomRadius * 0.45, y: mugBottom),
    controlPoint2: NSPoint(x: mugLeft, y: mugBottom + bottomRadius * 0.45)
)
body.line(to: NSPoint(x: mugLeft, y: mugTop - topRadius))
body.curve(
    to: NSPoint(x: mugLeft + topRadius, y: mugTop),
    controlPoint1: NSPoint(x: mugLeft, y: mugTop - topRadius / 2),
    controlPoint2: NSPoint(x: mugLeft + topRadius / 2, y: mugTop)
)
body.close()
fill(body, top: color(0xFBF6EF), bottom: color(0xE2D5C3))

// Пар: три волны тёплого цвета над кружкой
let steamColors = [color(0xFFC46B), color(0xF7A23B), color(0xFFC46B)]
for (index, offset) in [-78, 0, 78].enumerated() {
    let x = mugLeft + mugWidth / 2 + CGFloat(offset)
    let startY = mugTop + 50
    let height: CGFloat = index == 1 ? 210 : 170
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: x, y: startY))
    wave.curve(
        to: NSPoint(x: x, y: startY + height / 2),
        controlPoint1: NSPoint(x: x - 34, y: startY + height * 0.18),
        controlPoint2: NSPoint(x: x - 34, y: startY + height * 0.32)
    )
    wave.curve(
        to: NSPoint(x: x, y: startY + height),
        controlPoint1: NSPoint(x: x + 34, y: startY + height * 0.68),
        controlPoint2: NSPoint(x: x + 34, y: startY + height * 0.82)
    )
    wave.lineWidth = 30
    wave.lineCapStyle = .round
    steamColors[index].setStroke()
    wave.stroke()
}

NSGraphicsContext.restoreGraphicsState()

let png = bitmap.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("written \(outPath)")
