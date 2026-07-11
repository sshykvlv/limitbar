import AppKit

enum IconRenderer {
    enum Severity: Equatable {
        case normal, warn, danger
    }

    struct BarLevel: Equatable {
        let used: Double?        // 0…1, доля израсходованного; nil = нет данных
        let severity: Severity
    }

    /// Один бар на аккаунт. Заполнение = израсходовано (worstUtilization), цвет по нему же:
    /// >90% → danger (красный), >70% → warn (жёлтый), иначе normal (зелёный).
    static func barLevels(_ states: [AccountState]) -> [BarLevel] {
        states.map { state in
            switch state {
            case .ok(let u, _), .stale(let u, _, _):
                let used = min(max(u.worstUtilization / 100, 0), 1)
                let severity: Severity
                if u.worstUtilization > 90 { severity = .danger }
                else if u.worstUtilization > 70 { severity = .warn }
                else { severity = .normal }
                return BarLevel(used: used, severity: severity)
            case .failed, .pending:
                return BarLevel(used: nil, severity: .normal)
            }
        }
    }

    static func image(levels: [BarLevel]) -> NSImage {
        // Столбик на аккаунт, высота = сколько израсходовано у этой модели (снизу вверх),
        // цвет — зелёный/жёлтый/красный по уровню. Никаких цифр: столбики сами показывают
        // реальный статус каждой модели.
        let barW: CGFloat = 3, gap: CGFloat = 2, barH: CGFloat = 15, canvasH: CGFloat = 18
        let count = max(levels.count, 1)
        let width = CGFloat(count) * barW + CGFloat(count - 1) * gap + 2
        // Template оставляем только когда данных нет вовсе (пустой значок).
        let hasData = levels.contains { $0.used != nil }
        let img = NSImage(size: NSSize(width: width, height: canvasH), flipped: false) { _ in
            let y = (canvasH - barH) / 2
            for (i, level) in levels.enumerated() {
                let x = 1 + CGFloat(i) * (barW + gap)
                let track = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: barH),
                                         xRadius: barW / 2, yRadius: barW / 2)
                // Белая подложка столбика (фидбэк владельца 11.07).
                NSColor(white: 1.0, alpha: 0.5).setFill()
                track.fill()
                if let used = level.used {
                    let h = used > 0 ? max(barW, barH * used) : 0   // минимум — «точка», 0% — пусто
                    if h > 0 {
                        let fill = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: h),
                                                xRadius: barW / 2, yRadius: barW / 2)
                        fillColor(for: level.severity).setFill()
                        fill.fill()
                    }
                }
            }
            return true
        }
        img.isTemplate = !hasData
        return img
    }

    private static func fillColor(for severity: Severity) -> NSColor {
        switch severity {
        case .danger: return .systemRed
        case .warn: return .systemYellow
        case .normal: return .systemGreen
        }
    }
}
