import Foundation

// @unchecked Sendable: only ever touched from @MainActor contexts (AppDelegate, OAuthFlow) —
// never actually shared across threads, but the type isn't itself actor-isolated.
final class AccountStore: @unchecked Sendable {
    private let key = "accounts"
    private let defaults: UserDefaults
    private(set) var accounts: [Account] = []

    init(defaults: UserDefaults = .standard,
         hasClaudeMain: @escaping () -> Bool = { KeychainStore.claudeCodeTokens() != nil },
         hasCodex: @escaping () -> Bool = { CodexAuth.load() != nil }) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let list = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = list
        }
        discoverBuiltins(hasClaudeMain: hasClaudeMain(), hasCodex: hasCodex())
    }

    /// Автоподхват: основной Claude (если есть Keychain-запись) и Codex (если есть auth.json).
    private func discoverBuiltins(hasClaudeMain: Bool, hasCodex: Bool) {
        var changed = false
        if !accounts.contains(where: { $0.kind == .claudeMain }), hasClaudeMain {
            accounts.insert(Account(id: UUID(), name: "Claude", kind: .claudeMain, email: nil), at: 0)
            changed = true
        }
        if !accounts.contains(where: { $0.kind == .codex }), hasCodex {
            accounts.append(Account(id: UUID(), name: "Codex", kind: .codex, email: nil))
            changed = true
        }
        if changed { persist() }
    }

    func add(_ account: Account) { insertSorted(account); persist() }
    func rename(id: UUID, to name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].name = name; persist()
    }
    func remove(id: UUID) {
        accounts.removeAll { $0.id == id }
        KeychainStore.deleteOwn(accountID: id)
        persist()
    }

    /// Codex всегда последним.
    private func insertSorted(_ account: Account) {
        if let codexIdx = accounts.firstIndex(where: { $0.kind == .codex }), account.kind != .codex {
            accounts.insert(account, at: codexIdx)
        } else {
            accounts.append(account)
        }
    }

    private func persist() { defaults.set(try? JSONEncoder().encode(accounts), forKey: key) }
}
