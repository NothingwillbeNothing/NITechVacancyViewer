import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var isDemo = false
    @Published private(set) var isLoading = false
    @Published private(set) var snapshot: ScheduleSnapshot?
    @Published private(set) var now = Date()
    @Published var errorMessage: String?
    @Published private(set) var buildings: [Building] = []
    private let legacyCredentials = CredentialStore()
    private let cache = ScheduleCache()
    let campus = CampusSquareService()
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var demoTemplate: [Room] = []

    init() {
        do {
            buildings = try Self.resource("buildings", as: [Building].self)
            demoTemplate = try Self.resource("demo", as: [Room].self)
        } catch { errorMessage = "アプリのデータを読み込めませんでした。" }
    }

    var rooms: [Room] { snapshot?.rooms(on: now) ?? [] }
    var hasTodayData: Bool { snapshot?.rooms(on: now) != nil }
    var minute: Int { CampusClock.minute(now) }
    func room(named name: String) -> Room? { rooms.first { $0.name == name } }

    func start() {
        guard !isReady else { return }
        isReady = true
        // The new portal owns authentication. Remove passwords saved by 1.0;
        // new sessions use the portal's cookies and their device-only archive.
        try? legacyCredentials.clear()
        let remember = UserDefaults.standard.object(forKey: "rememberCampusSession") as? Bool ?? true
        if remember && UserDefaults.standard.bool(forKey: "hasCampusSession") {
            snapshot = cache.load()
            isSignedIn = snapshot?.rooms(on: now) != nil
            loadPortal(interactive: false, remember: remember)
        }
    }

    func signIn(remember: Bool) {
        UserDefaults.standard.set(remember, forKey: "rememberCampusSession")
        loadPortal(interactive: true, remember: remember)
    }

    private func loadPortal(interactive: Bool, remember: Bool? = nil) {
        beginOperation { [weak self] id in
            guard let self else { return }
            if let remember { try await campus.configureSession(remember: remember) }
            try Task.checkCancellation()
            let result = try await campus.fetch(interactive: interactive)
            try Task.checkCancellation()
            guard generation == id else { return }
            try cache.save(result)
            snapshot = result
            now = Date()
            isSignedIn = true
            isDemo = false
            UserDefaults.standard.set(
                UserDefaults.standard.object(forKey: "rememberCampusSession") as? Bool ?? true,
                forKey: "hasCampusSession"
            )
        }
    }

    func enterDemo() {
        stopOperation()
        isDemo = true
        isSignedIn = true
        errorMessage = nil
        now = Date()
        snapshot = makeDemo()
    }

    func refresh() {
        now = Date()
        if isDemo { snapshot = makeDemo(); return }
        guard !isLoading else { return }
        loadPortal(interactive: false)
    }

    func refreshAndWait() async {
        refresh()
        await operation?.value
    }

    func tick() {
        let oldDay = CampusClock.dayKey(now)
        now = Date()
        guard isSignedIn else { return }
        if isDemo && oldDay != CampusClock.dayKey(now) { snapshot = makeDemo() }
        else if !isDemo && !hasTodayData && !isLoading { refresh() }
    }

    func saveSessionBeforeBackgrounding() async {
        guard isSignedIn, !isDemo else { return }
        await campus.saveSessionBeforeBackgrounding()
    }

    func signOut() {
        if isDemo {
            stopOperation()
            resetSignedInState()
            return
        }
        beginOperation { [weak self] id in
            guard let self else { return }
            var cleanupError: Error?
            do { try await campus.clearSession() }
            catch { cleanupError = error }
            guard generation == id else { return }
            do { try cache.clear() }
            catch { if cleanupError == nil { cleanupError = error } }
            try? legacyCredentials.clear()
            UserDefaults.standard.set(false, forKey: "hasCampusSession")
            resetSignedInState()
            if let cleanupError { throw cleanupError }
        }
    }

    private func resetSignedInState() {
        snapshot = nil
        isDemo = false
        isSignedIn = false
        errorMessage = nil
    }

    private func makeDemo() -> ScheduleSnapshot {
        ScheduleSnapshot(fetchedAt: now, days: (0..<7).map {
            DailySchedule(date: CampusClock.dayKey(CampusClock.addingDays($0, to: now)), rooms: demoTemplate)
        })
    }

    private func stopOperation() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        campus.cancel()
        isLoading = false
    }

    private func beginOperation(_ action: @escaping (UUID) async throws -> Void) {
        stopOperation()
        let id = generation
        isLoading = true
        errorMessage = nil
        operation = Task { [weak self] in
            do { try await action(id) }
            catch is CancellationError { }
            catch {
                guard let self, generation == id else { return }
                if let failure = error as? ViewerError {
                    switch failure {
                    case .sessionExpired, .sessionStorage:
                        UserDefaults.standard.set(false, forKey: "hasCampusSession")
                        try? campus.invalidateSavedSession()
                        resetSignedInState()
                    default: break
                    }
                }
                errorMessage = error.localizedDescription
            }
            guard let self, generation == id else { return }
            isLoading = false
            operation = nil
        }
    }

    private static func resource<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw ViewerError.layoutChanged
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}
