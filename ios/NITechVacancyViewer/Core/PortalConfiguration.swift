import Foundation

enum PortalConfiguration {
    static let host = "aprkyomu-nitechict.msappproxy.net"
    static let legacyHost = "rpxkyomu.ict.nitech.ac.jp"
    static let mainURL = URL(string: "https://aprkyomu-nitechict.msappproxy.net/campusweb/campusportal.do?page=main&tabId=kh")!
    static let facilityURL = URL(string: "https://aprkyomu-nitechict.msappproxy.net/campusweb/campussquare.do?_flowId=KHW0001300-flow")!

    static func campusURL(_ url: URL) -> URL? {
        guard url.scheme == "https", let host = url.host,
              host == self.host || host == legacyHost else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = self.host
        return components?.url
    }

    static func isAllowedNavigation(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        if host == self.host { return true }
        if host.hasSuffix(".nitech.ac.jp") { return true }
        return host == "login.microsoftonline.com" || host.hasSuffix(".microsoftonline.com")
            || host == "login.microsoft.com" || host == "login.windows.net"
            || host == "login.live.com" || host.hasSuffix(".msauth.net")
    }

    static func isAllowedCookieDomain(_ domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty, let url = URL(string: "https://\(host)/"), url.host == host else { return false }
        // SSO cookies can be scoped to the parent authentication domain.
        return host == "nitech.ac.jp" || host == "microsoftonline.com" || host == "msauth.net"
            || host == "microsoft.com" || host == "windows.net" || host == "live.com"
            || isAllowedNavigation(url)
    }
}
