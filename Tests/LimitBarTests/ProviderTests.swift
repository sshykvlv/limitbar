import XCTest
@testable import LimitBar

final class ProviderTests: XCTestCase {
    func testOwnTokensRoundtrip() throws {
        let id = UUID()
        defer { KeychainStore.deleteOwn(accountID: id) }
        let t = OAuthTokens(accessToken: "test-access", refreshToken: "test-refresh",
                            expiresAt: Date(timeIntervalSince1970: 2_000_000_000))
        try KeychainStore.saveOwn(t, accountID: id)
        XCTAssertEqual(KeychainStore.loadOwn(accountID: id), t)
        KeychainStore.deleteOwn(accountID: id)
        XCTAssertNil(KeychainStore.loadOwn(accountID: id))
    }

    // Opt-in: чтение чужой записи "Claude Code-credentials" вызывает блокирующий
    // диалог Keychain у любого, кто запускает тесты. Гоняем только когда явно просят:
    // LIMITBAR_TEST_KEYCHAIN=1 swift test
    func testClaudeCodeTokensReadableOnOwnerMachine() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIMITBAR_TEST_KEYCHAIN"] == "1",
                          "set LIMITBAR_TEST_KEYCHAIN=1 to exercise real Keychain read")
        // На машине владельца запись существует; смок-проверка парсинга без вывода значений.
        if let t = KeychainStore.claudeCodeTokens() {
            XCTAssertGreaterThan(t.accessToken.count, 20)
            XCTAssertGreaterThan(t.expiresAt.timeIntervalSince1970, 1_700_000_000)
        }
    }

    func testClaudeProviderSuccess() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            XCTAssertTrue(req.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("claude-code/") ?? false)
            return (200, Data(#"{"five_hour":{"utilization":42,"resets_at":"2026-07-11T18:00:00Z"},"seven_day":{"utilization":13,"resets_at":"2026-07-14T09:00:00Z"}}"#.utf8))
        }
        let usage = try await ClaudeProvider(session: .mocked).fetchUsage(accessToken: "tok")
        XCTAssertEqual(usage.fiveHour?.utilization, 42)
    }

    func testClaudeProvider401() async {
        MockURLProtocol.handler = { _ in (401, Data()) }
        do { _ = try await ClaudeProvider(session: .mocked).fetchUsage(accessToken: "tok"); XCTFail() }
        catch { XCTAssertEqual(error as? FetchError, .unauthorized) }
    }

    func testClaudeProvider429() async {
        MockURLProtocol.handler = { _ in (429, Data()) }
        do { _ = try await ClaudeProvider(session: .mocked).fetchUsage(accessToken: "tok"); XCTFail() }
        catch { XCTAssertEqual(error as? FetchError, .rateLimited) }
    }

    func testCodexAuthFileParsing() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("auth-test.json")
        try #"{"tokens":{"access_token":"at","refresh_token":"rt","account_id":"acc"},"last_refresh":"2026-07-01T00:00:00Z"}"#
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let auth = try XCTUnwrap(CodexAuth.load(from: tmp))
        XCTAssertEqual(auth.accessToken, "at")
        XCTAssertEqual(auth.refreshToken, "rt")
    }

    func testCodexAuthMissingFileIsNil() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID()).json")
        XCTAssertNil(CodexAuth.load(from: missing))
    }

    func testCodexProviderSuccess() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data(#"{"rate_limit":{"primary_window":{"used_percent":12,"reset_at":1784360440},"secondary_window":{"used_percent":23,"reset_at":1784360440}}}"#.utf8))
        }
        let usage = try await CodexProvider(session: .mocked).fetchUsage(accessToken: "at")
        XCTAssertEqual(usage.fiveHour?.utilization, 12)
        XCTAssertEqual(usage.sevenDay?.utilization, 23)
    }

    func testCodexProvider401() async {
        MockURLProtocol.handler = { _ in (401, Data()) }
        do { _ = try await CodexProvider(session: .mocked).fetchUsage(accessToken: "at"); XCTFail() }
        catch { XCTAssertEqual(error as? FetchError, .unauthorized) }
    }
}
