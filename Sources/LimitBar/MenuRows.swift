import SwiftUI
import AppKit

struct AccountRowView: View {
    let name: String
    let state: AccountState
    let kind: AccountKind
    var email: String? = nil
    var plan: String? = nil

    // Иконок/плашек в строке нет (решение 2026-07-11): аккаунт — первой строкой
    // (главный сканируемый признак при нескольких аккаунтах одного сервиса),
    // сервис — второй, нейтральным цветом. Email уходит в hover-тултип.
    private var serviceLabel: String {
        switch kind {
        case .claudeMain, .claudeOAuth: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    private var identityHelp: String {
        var lines = [name, serviceLabel]
        if let plan, !plan.isEmpty { lines[1] += " · \(plan)" }
        if let email, !email.isEmpty { lines.append(email) }
        return lines.joined(separator: "\n")
    }

    @State private var hovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(hovered ? Color.white : Color.primary)
                        .lineLimit(1)
                    // Stale-бейдж живёт у имени, а не справа от гейджей: там он
                    // отъедал ширину у времени сброса и оно обрезалось.
                    if case .stale(_, _, let badge) = state {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10)).foregroundStyle(.orange)
                            .help(badge)
                    }
                }
                // Нейтральный вторичный текст (по гайдлайнам macOS), а не брендовый цвет:
                // сервис читается словом, смысловой цвет несут бары. На выделении — белый.
                Text(plan.map { "\(serviceLabel) · \($0)" } ?? serviceLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hovered ? Color.white.opacity(0.85) : Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }
            .frame(width: 148, alignment: .leading)
            .help(identityHelp)
            switch state {
            case .pending:
                gauges(usage: nil)
            case .failed(let badge):
                Label(badge, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                Spacer()
            case .ok(let usage, _), .stale(let usage, _, _):
                gauges(usage: usage)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: MenuRowFactory.rowWidth, height: MenuRowFactory.rowHeight, alignment: .leading)
        // Нативная подсветка выделения (фидбэк владельца 11.07): кастомные view-строки
        // NSMenu сам не подсвечивает — рисуем акцентный rounded-rect с инсетом 5pt,
        // как у системных пунктов; цвет — системный selection (следует за акцентом юзера).
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .selectedContentBackgroundColor))
                .opacity(hovered ? 1 : 0)
                .padding(.horizontal, 5)
        )
        .onHover { hovered = $0 }
    }

    // Кольца вернулись (фидбэк владельца 11.07: «выглядели хорошо, я бы их не убирал»),
    // но подпись переехала вбок: рядом с каждым кольцом — окно («5h»/«7d») и всегда
    // видимое абсолютное время сброса («когда», а не «через сколько»). Так строка
    // ниже и воздушнее, чем с подписью под кольцом.
    @ViewBuilder
    private func gauges(usage: Usage?) -> some View {
        HStack(spacing: 12) {
            RingGauge(label: "5h", window: usage?.fiveHour, hovered: hovered)
                .help(resetHelp(title: "5-hour window", window: usage?.fiveHour))
            RingGauge(label: "7d", window: usage?.sevenDay, hovered: hovered)
                .help(resetHelp(title: "Weekly window", window: usage?.sevenDay))
        }
    }

    /// Multi-line tooltip: "<title>\n<used>% used · <left>% left\nResets <abs> (<rel>)".
    private func resetHelp(title: String, window: UsageWindow?) -> String {
        guard let window else { return "\(title)\nNo data" }
        let used = Int(window.utilization)
        let remaining = 100 - used
        var lines = [title, "\(used)% used · \(remaining)% left"]
        if let resetsAt = window.resetsAt, let absolute = ResetClock.label(resetsAt) {
            let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .full
            lines.append("Resets \(absolute) (\(rel.localizedString(for: resetsAt, relativeTo: .now)))")
        }
        return lines.joined(separator: "\n")
    }
}

/// Абсолютное время сброса окна: сегодня — «19:00», иначе — «Tue 09:00»
/// (локале-зависимые форматы). Владелец 11.07: конкретное время полезнее,
/// чем «через сколько часов», — показываем его всегда, не только в тултипе.
enum ResetClock {
    static func label(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let date else { return nil }
        if date <= now { return "now" }
        let f = DateFormatter()
        f.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            f.setLocalizedDateFormatFromTemplate("jm")
        } else {
            f.setLocalizedDateFormatFromTemplate("EEE jm")
        }
        return f.string(from: date)
    }
}

/// Кольцо-гейдж (процент внутри, дуга с круглыми капами — заполнение заканчивается
/// закруглением, не рубленым краем) + сбоку колонка: окно («5h»/«7d») и абсолютное
/// время сброса. `window == nil` — нет данных: пустой трек, «—» внутри.
/// При исчерпании (>99%) время сброса становится главным ответом — красным и жирнее.
private struct RingGauge: View {
    let label: String
    let window: UsageWindow?
    var hovered: Bool = false

    private static let diameter: CGFloat = 22
    private static let lineWidth: CGFloat = 3

    private var fraction: Double {
        guard let window else { return 0 }
        return min(max(window.utilization / 100, 0), 1)
    }
    private var exhausted: Bool { (window?.utilization ?? 0) > 99 }

    private var ringColor: Color {
        let util = window?.utilization ?? 0
        if util > 90 { return Color(nsColor: .systemRed) }
        if util > 70 { return Color(nsColor: .systemYellow) }
        return Color(nsColor: .systemGreen)
    }

    // На выделенной (синей) строке серые/тёмные элементы теряют контраст —
    // на hover подкручиваем текст и трек под светлый фон.
    private var labelColor: Color { hovered ? .white.opacity(0.75) : Color(nsColor: .tertiaryLabelColor) }
    private var numberColor: Color { hovered ? .white : .primary }
    private var trackColor: Color { hovered ? .white.opacity(0.3) : Color(nsColor: .quaternaryLabelColor) }
    private var resetColor: Color {
        if hovered { return .white.opacity(exhausted ? 1 : 0.75) }
        return exhausted ? Color(nsColor: .systemRed) : Color(nsColor: .secondaryLabelColor)
    }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: Self.lineWidth)
                if window != nil, fraction > 0 {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(window.map { "\(Int($0.utilization))" } ?? "—")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(labelColor)
                Text(resetText)
                    .font(.system(size: 9, weight: exhausted ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(resetColor)
                    .lineLimit(1)
            }
            .frame(width: 60, alignment: .leading)
        }
    }

    private var resetText: String {
        guard let window else { return "" }
        guard let label = ResetClock.label(window.resetsAt) else { return "" }
        return "↻ \(label)"
    }
}

enum MenuRowFactory {
    static let rowWidth: CGFloat = 368
    // Height budget: кольцо 22pt (подпись сбоку, не снизу) vs текст-колонка ~24pt;
    // ~4pt воздуха сверху/снизу → 32pt. Компактнее и колец-с-подписью-снизу (38pt),
    // и горизонтальных баров (36pt).
    static let rowHeight: CGFloat = 32

    static func item(for account: Account, state: AccountState) -> NSMenuItem {
        let item = NSMenuItem()
        let row = AccountRowView(name: account.name, state: state, kind: account.kind,
                                  email: account.email, plan: account.plan)
        let host = NSHostingView(rootView: row)
        // Disable NSHostingView's own intrinsic-size layout so it can't leave stale sizing
        // slack in the parent NSMenu window (the "gap after Quit" gotcha). macOS 13+.
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight)
        item.view = host
        item.representedObject = account.id
        return item
    }
}
