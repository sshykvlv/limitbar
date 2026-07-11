import XCTest
@testable import LimitBar

final class OAuthTests: XCTestCase {
    func testPKCEPairIsValid() {
        let pair = PKCE.generate()
        XCTAssertGreaterThanOrEqual(pair.verifier.count, 43)
        XCTAssertFalse(pair.challenge.contains("="))   // base64url, no padding
        XCTAssertFalse(pair.challenge.contains("+"))
        XCTAssertFalse(pair.challenge.contains("/"))
        XCTAssertNotEqual(pair.verifier, pair.challenge)
    }

    func testCallbackParsing() {
        let parsed = OAuthFlow.parseCallback(requestLine: "GET /callback?code=abc123&state=xyz HTTP/1.1")
        XCTAssertEqual(parsed?.code, "abc123")
        XCTAssertEqual(parsed?.state, "xyz")
    }

    func testCallbackParsingRejectsWrongPath() {
        XCTAssertNil(OAuthFlow.parseCallback(requestLine: "GET /favicon.ico HTTP/1.1"))
    }
}
