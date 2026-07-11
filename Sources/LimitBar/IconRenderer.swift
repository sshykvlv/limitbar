import AppKit

enum IconRenderer {
    enum Severity: Equatable {
        case normal, warn, danger
    }

    struct BarLevel: Equatable {
        let remaining: Double?   // 0…1; nil = нет данных
        let severity: Severity
    }

    /// Severity — по худшему окну (worstUtilization): >90% использовано → danger,
    /// >70% → warn, иначе normal. danger по сути покрывает старый "hot" (<10% remaining).
    static func barLevels(_ states: [AccountState]) -> [BarLevel] {
        states.map { state in
            switch state {
            case .ok(let u, _), .stale(let u, _, _):
                let remaining = max(0, 1 - u.worstUtilization / 100)
                let severity: Severity
                if u.worstUtilization > 90 { severity = .danger }
                else if u.worstUtilization > 70 { severity = .warn }
                else { severity = .normal }
                return BarLevel(remaining: remaining, severity: severity)
            case .failed, .pending:
                return BarLevel(remaining: nil, severity: .normal)
            }
        }
    }

    static func image(levels: [BarLevel]) -> NSImage {
        // Тонкие столбцы — чтобы в строку меню помещалось больше аккаунтов.
        let barW: CGFloat = 2.5, gap: CGFloat = 2, barH: CGFloat = 15, canvasH: CGFloat = 18
        let count = max(levels.count, 1)
        let width = CGFloat(count) * barW + CGFloat(count - 1) * gap + 2
        // Цветовое кодирование (зелёный/жёлтый/красный) — картинка всегда цветная,
        // template оставляем только когда данных нет вовсе (пустой значок).
        let hasData = levels.contains { $0.remaining != nil }
        let img = NSImage(size: NSSize(width: width, height: canvasH), flipped: false) { _ in
            let y = (canvasH - barH) / 2
            for (i, level) in levels.enumerated() {
                let x = 1 + CGFloat(i) * (barW + gap)
                let track = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: barH),
                                         xRadius: barW / 2, yRadius: barW / 2)
                // Нейтральный трек, читаемый и на светлой, и на тёмной строке меню.
                NSColor(white: 0.5, alpha: 0.35).setFill()
                track.fill()
                if let remaining = level.remaining, remaining > 0 {
                    let h = max(barW, barH * remaining)   // минимум — «точка»
                    let fill = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: h),
                                            xRadius: barW / 2, yRadius: barW / 2)
                    fillColor(for: level.severity).setFill()
                    fill.fill()
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
