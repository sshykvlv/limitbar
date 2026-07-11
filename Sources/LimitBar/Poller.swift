import Foundation

@MainActor
final class Poller {
    nonisolated static let interval: TimeInterval = 60
    nonisolated static let backoffSchedule: [TimeInterval] = [120, 240, 480, 900]

    private let store: AccountStore
    private var states: [UUID: AccountState] = [:]
    private var backoffLevel: [UUID: Int] = [:]
    private var nextAllowed: [UUID: Date] = [:]
    private var timer: Timer?
    var onUpdate: (([UUID: AccountState]) -> Void)?

    private var codexAccessOverride: String?
    private var ownTokens: [UUID: OAuthTokens] = [:]

    init(store: AccountStore) { self.store = store }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollAll(force: false) }
        }
        Task { await pollAll(force: false) }
    }

    func pollNow() { Task { await pollAll(force: true) } }

    func state(for id: UUID) -> AccountState { states[id] ?? .pending }

    private func pollAll(force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for account in store.accounts {
                group.addTask { @MainActor in await self.poll(account, force: force) }
            }
        }
        onUpdate?(states)
    }

    private func poll(_ account: Account, force: Bool) async {
        let now = Date()
        if let gate = nextAllowed[account.id], now < gate, !force { return }
        if force, let last = lastFetch(account.id), now.timeIntervalSince(last) < 10 { return }
        nextAllowed[account.id] = now.addingTimeInterval(Self.interval - 1)
        do {
            let usage = try await fetchUsage(for: account)
            backoffLevel[account.id] = nil
            states[account.id] = .ok(usage, fetchedAt: Date())
        } catch FetchError.rateLimited {
            let lvl = min((backoffLevel[account.id] ?? -1) + 1, Self.backoffSchedule.count - 1)
            backoffLevel[account.id] = lvl
            nextAllowed[account.id] = Date().addingTimeInterval(Self.backoffSchedule[lvl])
            demote(account.id, badge: "rate-limited")
        } catch FetchError.unauthorized {
            demote(account.id, badge: badgeForAuthFailure(account))
        } catch {
            demote(account.id, badge: "offline")
        }
    }

    private func fetchUsage(for account: Account) async throws -> Usage {
        switch account.kind {
        case .claudeMain:
            guard let t = KeychainStore.claudeCodeTokens() else { throw FetchError.unauthorized }
            return try await ClaudeProvider().fetchUsage(accessToken: t.accessToken)
        case .claudeOAuth:
            guard var t = ownTokens[account.id] ?? KeychainStore.loadOwn(accountID: account.id) else {
                throw FetchError.unauthorized
            }
            if t.expiresAt < Date().addingTimeInterval(300) {
                t = try await ClaudeProvider().refresh(t)
                try? KeychainStore.saveOwn(t, accountID: account.id)
            }
            ownTokens[account.id] = t
            return try await ClaudeProvider().fetchUsage(accessToken: t.accessToken)
        case .codex:
            guard let auth = CodexAuth.load() else { throw FetchError.unauthorized }
            do {
                return try await CodexProvider().fetchUsage(accessToken: codexAccessOverride ?? auth.accessToken)
            } catch FetchError.unauthorized {
                let fresh = try await CodexProvider().refresh(auth)
                codexAccessOverride = fresh
                return try await CodexProvider().fetchUsage(accessToken: fresh)
            }
        }
    }

    private func badgeForAuthFailure(_ account: Account) -> String {
        switch account.kind {
        case .claudeMain: return "open Claude Code"
        case .claudeOAuth: return "re-login"
        case .codex: return "run codex login"
        }
    }

    private func demote(_ id: UUID, badge: String) {
        if case let .ok(usage, at) = states[id] { states[id] = .stale(usage, fetchedAt: at, badge: badge) }
        else if case let .stale(usage, at, _) = states[id] { states[id] = .stale(usage, fetchedAt: at, badge: badge) }
        else { states[id] = .failed(badge: badge) }
    }

    private func lastFetch(_ id: UUID) -> Date? {
        switch states[id] {
        case .ok(_, let at), .stale(_, let at, _): return at
        default: return nil
        }
    }
}
