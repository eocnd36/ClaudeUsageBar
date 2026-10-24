import AppKit
import ClaudeUsageCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @AppStorage(AppSettings.menuBarStyle) private var styleRaw = MenuBarStyle.sessionAndWeekly.rawValue

    private var style: MenuBarStyle { MenuBarStyle(rawValue: styleRaw) ?? .sessionAndWeekly }

    var body: some View {
        HStack(spacing: 4) {
            if store.snapshot == nil, store.error != nil {
                Image(systemName: "exclamationmark.circle")
            } else {
                Image(nsImage: GaugeIcon.image(percent: store.session?.percent))
            }
            if let text = MenuBarFormatter.text(
                style: style, snapshot: store.snapshot, now: store.now, countdown: Formatters.countdown
            ) {
                Text(text).monospacedDigit()
            }
        }
        .accessibilityLabel(Text("Claude usage"))
    }
}

/// 메뉴바용 원형 게이지. 평소에는 템플릿 이미지(메뉴바 색에 맞춰 흑/백)로 그리고,
/// 90% 이상이면 한눈에 보이도록 빨간색으로 그립니다.
enum GaugeIcon {
    private static var cache: [Int: NSImage] = [:]

    static func image(percent: Double?) -> NSImage {
        let key = percent.map { Int($0.rounded()) } ?? -1
        if let cached = cache[key] { return cached }

        let critical = key >= 90
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat = 2.2
            let ring = rect.insetBy(dx: lineWidth / 2 + 1, dy: lineWidth / 2 + 1)
            let center = NSPoint(x: rect.midX, y: rect.midY)

            let trackColor = critical ? NSColor.secondaryLabelColor : NSColor.black.withAlphaComponent(0.3)
            trackColor.setStroke()
            let track = NSBezierPath(ovalIn: ring)
            track.lineWidth = lineWidth
            track.stroke()

            if key > 0 {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: ring.width / 2,
                    startAngle: 90,
                    endAngle: 90 - 360 * CGFloat(min(key, 100)) / 100,
                    clockwise: true
                )
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                (critical ? NSColor.systemRed : NSColor.black).setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = !critical
        cache[key] = image
        return image
    }
}
