import AppKit

// Заглушка — реальная реализация в Task 12 (Updates). OAuthFlow — see OAuthFlow.swift (Task 11).
enum Updates {
    static func check(announce: Bool) {
        NSWorkspace.shared.open(URL(string: "https://github.com/sashayakovlev/limitbar/releases")!)
    }
}
