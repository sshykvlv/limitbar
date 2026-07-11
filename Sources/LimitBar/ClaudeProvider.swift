import Foundation

struct ClaudeProvider {
    static let userAgent = "claude-code/2.0.0"   // without this UA header the endpoint puts us in an aggressive 429 bucket
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchUsage(accessToken: String) async throws -> Usage {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw FetchError.network(error.localizedDescription) }
        switch (resp as! HTTPURLResponse).statusCode {
        case 200: return try ClaudeUsageParser.parse(data)
        case 401, 403: throw FetchError.unauthorized
        case 429: throw FetchError.rateLimited
        case let s: throw FetchError.badResponse("HTTP \(s)")
        }
    }

    // Token refresh for Claude Code's own OAuth tokens — used by later tasks (Poller, OAuth flow), not exercised by this task's tests. Keep it; it's not dead code.
    func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        var req = URLRequest(url: URL(string: ClaudeOAuthConstants.tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": ClaudeOAuthConstants.clientID,
        ])
        let (data, resp) = try await session.data(for: req)
        guard (resp as! HTTPURLResponse).statusCode == 200,
              let d = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = d["access_token"] as? String,
              let expiresIn = (d["expires_in"] as? NSNumber)?.doubleValue
        else { throw FetchError.unauthorized }
        let refresh = d["refresh_token"] as? String ?? tokens.refreshToken
        return OAuthTokens(accessToken: access, refreshToken: refresh,
                           expiresAt: Date().addingTimeInterval(expiresIn))
    }
}

enum ClaudeOAuthConstants {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"  // Claude Code's public OAuth client_id
    static let authorizeURL = "https://claude.ai/oauth/authorize"
    static let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    static let redirectURI = "http://localhost:54545/callback"
    static let scopes = "org:create_api_key user:profile user:inference"
}
