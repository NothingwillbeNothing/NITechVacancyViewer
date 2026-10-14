import Foundation
import Security
import WebKit

@MainActor
protocol CampusSessionArchiving {
    func load() throws -> [SessionCookie]
    func save(_ cookies: [HTTPCookie]) throws
    func clear() throws
}

struct CampusSessionStore: CampusSessionArchiving {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "NITechVacancyViewer") + ".campus-session",
         kSecAttrAccount as String: "browser-cookies"]
    }

    func load() throws -> [SessionCookie] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ViewerError.credentialStorage(status)
        }
        do { return try JSONDecoder().decode([SessionCookie].self, from: data) }
        catch { throw ViewerError.sessionStorage }
    }

    func save(_ cookies: [HTTPCookie]) throws {
        let records = SessionCookie.capture(cookies)
        guard !records.isEmpty else { try clear(); return }
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(records),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw ViewerError.credentialStorage(added) }
        } else if status != errSecSuccess { throw ViewerError.credentialStorage(status) }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ViewerError.credentialStorage(status)
        }
    }
}

/// Restore once, before the first request. Thereafter WebKit owns cookie rotation
/// and deletion; an old archive must never resurrect a cookie during a refresh.
@MainActor
final class CampusSessionPersistence: NSObject, WKHTTPCookieStoreObserver {
    private let store: CampusSessionArchiving
    private var cookieStore: WKHTTPCookieStore?
    private var generation = UUID()
    private var revision = 0
    private var canSave = false
    private var saveTask: Task<Void, Never>?
    var onFailure: ((Error) -> Void)?

    init(store: CampusSessionArchiving? = nil) {
        self.store = store ?? CampusSessionStore()
        super.init()
    }

    func stop() {
        generation = UUID()
        canSave = false
        saveTask?.cancel()
        saveTask = nil
        cookieStore?.remove(self)
        cookieStore = nil
    }

    func restore(into cookies: WKHTTPCookieStore) async throws {
        guard cookieStore !== cookies else { return }
        stop()
        let id = generation
        let saved = try store.load()
        let existing = await cookies.allCookies()
        for cookie in SessionCookie.missingCookies(from: saved, alongside: existing) {
            try Task.checkCancellation()
            guard generation == id else { throw CancellationError() }
            await cookies.setCookie(cookie)
        }
        try Task.checkCancellation()
        guard generation == id else { throw CancellationError() }
        cookieStore = cookies
        cookies.add(self)
    }

    func observe(_ cookies: WKHTTPCookieStore) {
        stop()
        cookieStore = cookies
        cookies.add(self)
    }

    func saveConfirmedSession() async throws {
        guard let cookies = cookieStore else { return }
        let id = generation
        // If a cookie changes during the read, read again before committing it.
        while true {
            let change = revision
            let values = await cookies.allCookies()
            try Task.checkCancellation()
            guard generation == id else { throw CancellationError() }
            if revision != change { continue }
            try store.save(values)
            break
        }
        canSave = true
    }

    func clear() throws {
        stop()
        try store.clear()
    }

    func saveIfConfirmed() async throws {
        guard canSave else { return }
        try await saveConfirmedSession()
    }

    func cookiesDidChange(in cookies: WKHTTPCookieStore) {
        guard cookieStore === cookies else { return }
        revision += 1
        guard canSave else { return }
        let change = revision
        let id = generation
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            let values = await cookies.allCookies()
            guard let self, !Task.isCancelled, self.generation == id,
                  self.revision == change, self.canSave else { return }
            do { try self.store.save(values) }
            catch { self.onFailure?(error) }
        }
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }
}
