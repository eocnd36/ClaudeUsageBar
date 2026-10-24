#!/usr/bin/env swift
// 앱 아이콘(Resources/AppIcon.icns)을 코드로 그립니다.
// 사용법: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS 아이콘 그리드: 1024 캔버스 안에 824 크기의 둥근 사각형
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(red: 0.93, green: 0.55, blue: 0.40, alpha: 1),
        NSColor(red: 0.74, green: 0.33, blue: 0.24, alpha: 1),
    ])!.draw(in: tilePath, angle: -90)

    let center = NSPoint(x: 512 * s, y: 512 * s)
    let radius = 250 * s
    let lineWidth = 92 * s

    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = lineWidth
    NSColor.white.withAlphaComponent(0.25).setStroke()
    track.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * 0.68, clockwise: true)
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()

    // 가운데 점: 진행 중인 세션
    let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 46 * s, y: center.y - 46 * s, width: 92 * s, height: 92 * s))
    NSColor.white.setFill()
    dot.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(1) }
print("✓ \(output)")
