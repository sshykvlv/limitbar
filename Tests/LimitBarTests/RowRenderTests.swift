import XCTest
import SwiftUI
@testable import LimitBar

/// Не проверка, а инструмент: рендерит AccountRowView во всех состояниях в PNG,
/// чтобы смотреть вёрстку строки без запуска приложения и открытия меню.
/// Запуск: `LIMITBAR_RENDER_DIR=/tmp/rows swift test --filter RowRenderTests`
/// Без переменной окружения — скип (в обычном прогоне ничего не пишет).
final class RowRenderTests: XCTestCase {
    @MainActor
    func testRenderRowStates() throws {
        guard let dir = ProcessInfo.processInfo.environment["LIMITBAR_RENDER_DIR"] else {
            throw XCTSkip("set LIMITBAR_RENDER_DIR to render row previews")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let now = Date()
        let exhausted = Usage(
            fiveHour: UsageWindow(utilization: 100, resetsAt: now.addingTimeInterval(82 * 60)),
            sevenDay: UsageWindow(utilization: 87, resetsAt: now.addingTimeInterval(2.6 * 86400)))
        let working = Usage(
            fiveHour: UsageWindow(utilization: 42, resetsAt: now.addingTimeInterval(3.2 * 3600)),
            sevenDay: UsageWindow(utilization: 18, resetsAt: now.addingTimeInterval(4.8 * 86400)))
        let calm = Usage(
            fiveHour: UsageWindow(utilization: 8, resetsAt: now.addingTimeInterval(4.6 * 3600)),
            sevenDay: UsageWindow(utilization: 74, resetsAt: now.addingTimeInterval(1.9 * 86400)))

        let rows: [(String, AccountRowView)] = [
            ("1-exhausted", AccountRowView(name: "Personal", state: .ok(exhausted, fetchedAt: now),
                                           kind: .claudeOAuth, email: "sasha@example.com", plan: "Max 20x")),
            ("2-working", AccountRowView(name: "Work", state: .ok(working, fetchedAt: now),
                                         kind: .claudeMain, email: "work@example.com", plan: "Pro")),
            ("3-calm-yellow7d", AccountRowView(name: "Codex", state: .ok(calm, fetchedAt: now),
                                               kind: .codex, email: "sasha@example.com", plan: "Plus")),
            ("4-stale", AccountRowView(name: "Personal", state: .stale(working, fetchedAt: now, badge: "offline"),
                                       kind: .claudeOAuth, plan: "Max 20x")),
            ("5-pending", AccountRowView(name: "Claude", state: .pending, kind: .claudeMain)),
            ("6-failed", AccountRowView(name: "Codex", state: .failed(badge: "run codex login"), kind: .codex)),
        ]
        for (name, row) in rows {
            let renderer = ImageRenderer(content: row.frame(width: MenuRowFactory.rowWidth,
                                                            height: MenuRowFactory.rowHeight))
            renderer.scale = 2
            guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("render failed for \(name)"); continue
            }
            try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }
}
