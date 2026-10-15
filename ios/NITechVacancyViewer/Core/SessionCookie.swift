import Foundation

/// Includes session cookies, whose server-side lifetime is only known to the portal.
/// Never turn Max-Age into a new lifetime when restoring a saved cookie.
struct SessionCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    let secure: Bool
    let httpOnly: Bool
    let sessionOnly: Bool
    let sameSite: String?

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expires = cookie.expiresDate
        secure = cookie.isSecure
        httpOnly = cookie.isHTTPOnly
        sessionOnly = cookie.isSessionOnly
        sameSite = cookie.properties?[HTTPCookiePropertyKey("SameSite")] as? String
    }

    func restore(at now: Date = Date()) -> HTTPCookie? {
        guard PortalConfiguration.isAllowedCookieDomain(domain),
              expires.map({ $0 > now }) ?? true else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path,
            .discard: sessionOnly ? "TRUE" : "FALSE"
        ]
        // Let Foundation use its default cookie version: explicitly supplying
        // Version can make Darwin ignore Expires for Max-Age/version-1 cookies.
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires { properties[.expires] = expires }
        if let sameSite { properties[HTTPCookiePropertyKey("SameSite")] = sameSite }
        return HTTPCookie(properties: properties)
    }

    static func capture(_ cookies: [HTTPCookie], at now: Date = Date()) -> [SessionCookie] {
        cookies.filter {
            PortalConfiguration.isAllowedCookieDomain($0.domain)
                && ($0.expiresDate.map { $0 > now } ?? true)
        }.map(SessionCookie.init)
    }

    static func missingCookies(from saved: [SessionCookie], alongside existing: [HTTPCookie],
                               at now: Date = Date()) -> [HTTPCookie] {
        saved.compactMap { $0.restore(at: now) }.filter { cookie in
            !existing.contains {
                $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
                    && ($0.expiresDate.map { $0 > now } ?? true)
            }
        }
    }
}
