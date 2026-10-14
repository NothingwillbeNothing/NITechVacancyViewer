import XCTest
#if SWIFT_PACKAGE
@testable import NITechVacancyCore
#endif

final class SessionCookieTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func cookie(value: String = "session-token", domain: String = PortalConfiguration.host,
                        path: String = "/campusweb", expires: Date? = nil) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "JSESSIONID", .value: value, .domain: domain, .path: path,
            .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE",
            HTTPCookiePropertyKey("SameSite"): "lax"
        ]
        if let expires { properties[.expires] = expires }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }

    func testSessionCookieSurvivesArchiveWithoutInventingAnExpiry() throws {
        let original = try cookie()
        let data = try JSONEncoder().encode(SessionCookie.capture([original], at: now))
        let saved = try JSONDecoder().decode([SessionCookie].self, from: data)
        let restored = try XCTUnwrap(saved.first?.restore(at: now.addingTimeInterval(86_400)))
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.value, original.value)
        XCTAssertEqual(restored.domain, original.domain)
        XCTAssertEqual(restored.path, original.path)
        XCTAssertNil(restored.expiresDate)
        XCTAssertEqual(restored.isSessionOnly, original.isSessionOnly)
        XCTAssertTrue(restored.isSecure)
        XCTAssertTrue(restored.isHTTPOnly)
        XCTAssertEqual(restored.properties?[HTTPCookiePropertyKey("SameSite")] as? String, "lax")
    }

    func testPersistentCookieKeepsOriginalExpiryAndExpiresAtBoundary() throws {
        let expiry = now.addingTimeInterval(3600)
        let saved = SessionCookie(try cookie(expires: expiry))
        XCTAssertEqual(saved.restore(at: now)?.expiresDate, expiry)
        XCTAssertNotNil(saved.restore(at: expiry.addingTimeInterval(-1)))
        XCTAssertNil(saved.restore(at: expiry))
        XCTAssertNil(saved.restore(at: expiry.addingTimeInterval(1)))
    }

    func testMaxAgeDoesNotRestartAfterRestoration() throws {
        let original = try XCTUnwrap(HTTPCookie(properties: [
            .name: "proxy-auth", .value: "test-token", .domain: PortalConfiguration.host,
            .path: "/", .version: "1", .maximumAge: "3600", .secure: "TRUE"
        ]))
        let saved = SessionCookie(original)
        let expiry = try XCTUnwrap(original.expiresDate)
        let restored = try XCTUnwrap(saved.restore(at: expiry.addingTimeInterval(-60)))
        XCTAssertEqual(try XCTUnwrap(restored.expiresDate).timeIntervalSince1970,
                       expiry.timeIntervalSince1970, accuracy: 1)
        XCTAssertNil(restored.properties?[.maximumAge])
        XCTAssertNil(saved.restore(at: expiry))
    }

    func testCaptureFiltersExpiredAndUnrelatedCookies() throws {
        let records = SessionCookie.capture([
            try cookie(), try cookie(domain: "login.microsoftonline.com"),
            try cookie(domain: ".microsoftonline.com"),
            try cookie(domain: "slb4oam.ict.nitech.ac.jp"),
            try cookie(domain: "attacker.test"),
            try cookie(expires: now)
        ], at: now)
        XCTAssertEqual(records.count, 4)
    }

    func testCookieDomainsRejectLookalikesAndMalformedHosts() {
        for host in ["", "msappproxy.net", ".com", "nitech.ac.jp.attacker.test",
                     "login.microsoftonline.com.attacker.test", "other.msappproxy.net",
                     "attacker.test/path", "user@login.microsoftonline.com"] {
            XCTAssertFalse(PortalConfiguration.isAllowedCookieDomain(host), host)
        }
        for host in [PortalConfiguration.host, ".nitech.ac.jp", ".microsoftonline.com",
                     ".msauth.net", ".live.com", ".windows.net", ".microsoft.com"] {
            XCTAssertTrue(PortalConfiguration.isAllowedCookieDomain(host), host)
        }
    }

    func testRestoreAlsoRejectsAnUnrelatedArchivedDomain() throws {
        XCTAssertNil(SessionCookie(try cookie(domain: "attacker.test")).restore(at: now))
    }

    func testNewerWebKitCookieTakesPrecedenceButDifferentPathsAreRestored() throws {
        let saved = [SessionCookie(try cookie(value: "old")),
                     SessionCookie(try cookie(value: "another-path", path: "/"))]
        let result = SessionCookie.missingCookies(from: saved,
            alongside: [try cookie(value: "rotated")], at: now)
        XCTAssertEqual(result.map(\.value), ["another-path"])
    }

    func testExpiredWebKitCookieDoesNotBlockAValidSavedCookie() throws {
        let result = SessionCookie.missingCookies(from: [SessionCookie(try cookie())],
            alongside: [try cookie(value: "expired", expires: now)], at: now)
        XCTAssertEqual(result.map(\.value), ["session-token"])
    }

    func testExpiryMessageRequestsAnotherLogin() {
        let message = ViewerError.sessionExpired.localizedDescription
        XCTAssertTrue(message.contains("有効期限"))
        XCTAssertTrue(message.contains("再度ログイン"))
    }
}
