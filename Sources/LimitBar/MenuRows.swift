import SwiftUI
import AppKit

struct AccountRowView: View {
    let name: String
    let state: AccountState
    let kind: AccountKind
    var email: String? = nil
    var plan: String? = nil

    private var secondaryLine: String? {
        guard let email, !email.isEmpty else { return nil }
        if let plan, !plan.isEmpty { return "\(email) · \(plan)" }
        return email
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ProviderTag(kind: kind)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 108, alignment: .leading)
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
        RingGauge(value: window?.utilization, caption: caption, color: gaugeColor(util))
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

/// Small brand-colored label identifying the provider (CLAUDE / CODEX) so the model
/// is readable at a glance regardless of the account's display name.
private struct ProviderTag: View {
    let kind: AccountKind

    private var text: String {
        switch kind {
        case .claudeMain, .claudeOAuth: return "CLAUDE"
        case .codex: return "CODEX"
        }
    }

    private var tint: Color {
        switch kind {
        case .claudeMain, .claudeOAuth: return Color(nsColor: NSColor(srgbRed: 0.80, green: 0.44, blue: 0.31, alpha: 1)) // Anthropic clay
        case .codex: return Color(nsColor: NSColor(srgbRed: 0.36, green: 0.38, blue: 0.42, alpha: 1))                    // graphite
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .frame(width: 52, alignment: .leading)
    }
}

/// A small circular utilization ring: faint background track + a clockwise-filling
/// foreground arc starting at 12 o'clock, the percentage centered, and a caption below.
/// `value == nil` means "no data" — only the faint track and a "—" are drawn.
private struct RingGauge: View {
    let value: Double?
    let caption: String
    let color: Color

    private static let diameter: CGFloat = 22
    private static let lineWidth: CGFloat = 3

    private var fraction: Double {
        guard let value else { return 0 }
        return min(max(value / 100, 0), 1)
    }

    var body: some View {
        VStack(spacing: 1.5) {
            ZStack {
                Circle()
                    .stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: Self.lineWidth)
                if value != nil {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(value.map { "\(Int($0))" } ?? "—")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: Self.diameter, height: Self.diameter)
                    .multilineTextAlignment(.center)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            Text(caption)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
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
