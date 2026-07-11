import Foundation

struct CodexAuth: Equatable {
    let accessToken: String
    let refreshToken: String

    static var defaultURL: URL {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return home.appendingPathComponent("auth.json")
    }

    // Read-only: never write auth.json back — it belongs to the codex CLI.
    static func load(from url: URL = defaultURL) -> CodexAuth? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String,
              let refresh = tokens["refresh_token"] as? String
        else { return nil }
        return CodexAuth(accessToken: access, refreshToken: refresh)
    }
}

struct CodexProvider {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchUsage(accessToken: String) async throws -> Usage {
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw FetchError.network(error.localizedDescription) }
        switch (resp as! HTTPURLResponse).statusCode {
        case 200: return try CodexUsageParser.parse(data)
        case 401, 403: throw FetchError.unauthorized
        case 429: throw FetchError.rateLimited
        case let s: throw FetchError.badResponse("HTTP \(s)")
        }
    }

    // In-memory refresh only: auth.json is never touched. Used by later tasks (Poller);
    // not exercised by this task's tests. Endpoint/client_id are best-effort from
    // CodexBar reverse-engineering — unverified until a real 401 happens against them.
    func refresh(_ auth: CodexAuth) async throws -> String {
        var req = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": auth.refreshToken,
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",   // codex CLI's public client_id
            "scope": "openid profile email",
        ])
        let (data, resp) = try await session.data(for: req)
        guard (resp as! HTTPURLResponse).statusCode == 200,
              let d = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = d["access_token"] as? String
        else { throw FetchError.unauthorized }
        return access
    }
}
