import Foundation
import WebKit
import Darwin

/// Runs on macOS using real WebKit cookie stores and an in-memory Keychain stand-in.
/// No university credentials, simulator, or access to the runner's Keychain is needed.
@main
@MainActor
struct SessionPersistenceChecks {
    final class Archive: CampusSessionArchiving {
        var records: [SessionCookie] = []
        var saves = 0
        func load() throws -> [SessionCookie] { records }
        func save(_ cookies: [HTTPCookie]) throws {
            records = SessionCookie.capture(cookies)
            saves += 1
        }
        func clear() throws { records = [] }
    }

    static func cookie(_ value: String) -> HTTPCookie {
        HTTPCookie(properties: [.name: "JSESSIONID", .value: value,
            .domain: PortalConfiguration.host, .path: "/campusweb",
            .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"])!
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "SessionChecks", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func allCookies(_ store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    static func waitUntil(_ operation: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try require(false, "Cookie observer did not finish within five seconds: \(operation)")
    }

    static func main() {
        // CFNetwork delivers cookie notifications through the main run loop.
        // An async command-line main alone only pumps the dispatch queue.
        Task { @MainActor in
            do {
                try await runChecks()
                exit(0)
            } catch {
                fputs("Session check failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        RunLoop.main.run()
    }

    static func runChecks() async throws {
        let archive = Archive()
        let firstData = WKWebsiteDataStore.nonPersistent()
        let first = CampusSessionPersistence(store: archive)
        try await first.restore(into: firstData.httpCookieStore)
        await firstData.httpCookieStore.setCookie(cookie("first-login"))
        try await first.saveConfirmedSession()
        try require(archive.records.first?.value == "first-login", "Confirmed login was not archived")
        first.stop()
        print("PASS: verified session cookie is saved")

        let secondData = WKWebsiteDataStore.nonPersistent()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = secondData
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.loadHTMLString("<html><body>Cookie store checks</body></html>", baseURL: nil)
        defer { browser.stopLoading() }
        let second = CampusSessionPersistence(store: archive)
        try await second.restore(into: secondData.httpCookieStore)
        let restored = await allCookies(secondData.httpCookieStore)
        try require(restored.first?.value == "first-login", "Session cookie did not survive a new store")
        try require(restored.first?.isHTTPOnly == true, "Restoration removed HttpOnly")
        try await second.saveConfirmedSession()
        print("PASS: session cookie is restored before use")

        await secondData.httpCookieStore.setCookie(cookie("rotated-login"))
        try await waitUntil("rotation") { archive.records.first?.value == "rotated-login" }
        print("PASS: server cookie rotation updates the archive")

        let activeCookie = (await allCookies(secondData.httpCookieStore))[0]
        await withCheckedContinuation { continuation in
            secondData.httpCookieStore.delete(activeCookie) { continuation.resume() }
        }
        try await waitUntil("deletion") { archive.records.isEmpty }
        try await second.restore(into: secondData.httpCookieStore)
        let afterDeletion = await allCookies(secondData.httpCookieStore)
        try require(afterDeletion.isEmpty, "Refresh resurrected a deleted cookie")
        print("PASS: deleted cookies stay deleted during refresh")

        await secondData.httpCookieStore.setCookie(cookie("before-logout"))
        try await waitUntil("before logout") { !archive.records.isEmpty }
        let backgroundSave = Task { try await second.saveIfConfirmed() }
        try second.clear()
        _ = try? await backgroundSave.value
        await secondData.httpCookieStore.setCookie(cookie("after-logout"))
        try await Task.sleep(nanoseconds: 150_000_000)
        try require(archive.records.isEmpty, "Pending save recreated the archive after logout")
        print("PASS: logout prevents pending and future observer saves")

        let freshData = WKWebsiteDataStore.nonPersistent()
        let fresh = CampusSessionPersistence(store: archive)
        fresh.observe(freshData.httpCookieStore)
        await freshData.httpCookieStore.setCookie(cookie("unconfirmed-login"))
        try await fresh.saveIfConfirmed()
        try require(archive.records.isEmpty, "Incomplete authentication was archived")
        fresh.stop()
        print("PASS: unconfirmed logins are not saved")
    }
}
