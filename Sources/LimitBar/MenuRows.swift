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
    // сервис — второй, окрашенным словом. Email уходит в hover-тултип.
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
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hovered ? Color.white : Color.primary)
                    .lineLimit(1)
                // Нейтральный вторичный текст (по гайдлайнам macOS), а не брендовый цвет:
                // сервис читается словом, смысловой цвет несут кольца. На выделении — белый.
                Text(plan.map { "\(serviceLabel) · \($0)" } ?? serviceLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hovered ? Color.white.opacity(0.85) : Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }
            .frame(width: 168, alignment: .leading)
            .help(identityHelp)
            switch state {
            case .pending:
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    ringGauge(title: "5-hour window", label: "5h", window: nil)
                    ringGauge(title: "Weekly window", label: "7d", window: nil)
                }
            case .failed(let badge):
                Label(badge, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                Spacer()
            case .ok(let usage, _), .stale(let usage, _, _):
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    ringGauge(title: "5-hour window", label: "5h", window: usage.fiveHour)
                    ringGauge(title: "Weekly window", label: "7d", window: usage.sevenDay)
                }
                if case .stale(_, _, let badge) = state {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                        .help(badge)
                }
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

    /// One ring gauge + detailed hover tooltip. When the window is essentially exhausted
    /// (>90% used), the caption switches from "5h"/"7d" to when it refreshes (e.g. "↻2h").
    @ViewBuilder
    private func ringGauge(title: String, label: String, window: UsageWindow?) -> some View {
        let util = window?.utilization ?? 0
        let caption: String = {
            if let window, window.utilization > 90, let short = shortReset(window.resetsAt) {
                return "↻\(short)"
            }
            return label
        }()
        RingGauge(value: window?.utilization, caption: caption, color: gaugeColor(util), hovered: hovered)
            .help(resetHelp(title: title, window: window))
    }

    /// Заполнение = израсходовано; цвет по остатку: спокойно — зелёный, ближе к концу — жёлтый/красный.
    private func gaugeColor(_ utilization: Double) -> Color {
        if utilization > 90 { return Color(nsColor: .systemRed) }
        if utilization > 70 { return Color(nsColor: .systemYellow) }
        return Color(nsColor: .systemGreen)
    }

    /// Компактное «через сколько сбросится»: 45m / 2h / 3d.
    private func shortReset(_ date: Date?) -> String? {
        guard let date else { return nil }
        let secs = date.timeIntervalSinceNow
        if secs <= 0 { return "now" }
        let mins = Int(secs / 60)
        if mins < 60 { return "\(max(mins, 1))m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        return "\(hrs / 24)d"
    }

    /// Multi-line tooltip: "<title>\n<used>% used · <left>% left\nResets <abs> (<rel>)".
    private func resetHelp(title: String, window: UsageWindow?) -> String {
        guard let window else { return "\(title)\nNo data" }
        let used = Int(window.utilization)
        let remaining = 100 - used
        var lines = [title, "\(used)% used · \(remaining)% left"]
        if let resetsAt = window.resetsAt {
            let absolute: String
            if Calendar.current.isDateInToday(resetsAt) {
                let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
                absolute = f.string(from: resetsAt)
            } else {
                let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
                absolute = f.string(from: resetsAt)
            }
            let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .full
            lines.append("Resets \(absolute) (\(rel.localizedString(for: resetsAt, relativeTo: .now)))")
        }
        return lines.joined(separator: "\n")
    }
}

/// A small circular utilization ring: faint background track + a clockwise-filling
/// foreground arc starting at 12 o'clock, the percentage centered, and a caption below.
/// `value == nil` means "no data" — only the faint track and a "—" are drawn.
private struct RingGauge: View {
    let value: Double?
    let caption: String
    let color: Color
    var hovered: Bool = false

    private static let diameter: CGFloat = 22
    private static let lineWidth: CGFloat = 3

    private var fraction: Double {
        guard let value else { return 0 }
        return min(max(value / 100, 0), 1)
    }

    // На выделенной (синей) строке серые/тёмные элементы теряют контраст —
    // на hover подкручиваем цифру/подпись/трек под светлый фон.
    private var numberColor: Color { hovered ? .white : .primary }
    private var captionColor: Color { hovered ? .white.opacity(0.75) : Color(nsColor: .tertiaryLabelColor) }
    private var trackColor: Color { hovered ? .white.opacity(0.3) : Color(nsColor: .quaternaryLabelColor) }

    var body: some View {
        VStack(spacing: 1.5) {
            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: Self.lineWidth)
                if value != nil {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(value.map { "\(Int($0))" } ?? "—")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .frame(width: Self.diameter, height: Self.diameter)
                    .multilineTextAlignment(.center)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            Text(caption)
                .font(.system(size: 8))
                .foregroundStyle(captionColor)
        }
    }
}

enum MenuRowFactory {
    static let rowWidth: CGFloat = 322
    // Height budget: 22pt ring + 1.5pt spacing + ~9pt caption ≈ 33pt (tallest element)
    // vs. the two-line text column (~13 + 1 + ~10 ≈ 24pt). ~3pt padding top/bottom → 38pt.
    static let rowHeight: CGFloat = 38

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
