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
    private let credentials = CredentialStore()
    private let cache = ScheduleCache()
    private let campus = CampusSquareService()
    private let auth = AuthenticationService()
    private var token: String?
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
        defer { isReady = true }
        do {
            if let saved = try credentials.load() {
                isSignedIn = true
                snapshot = cache.load()
                beginSignIn(saved, remember: nil)
            }
        } catch { report(error) }
    }

    func signIn(username: String, password: String, remember: Bool) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if username == "demoMode" && password == "demoMode" { enterDemo(); return }
        guard !username.isEmpty, !password.isEmpty,
              !username.contains("\n"), !username.contains("\r"),
              !password.contains("\n"), !password.contains("\r") else {
            errorMessage = "基盤IDとパスワードを入力してください。"
            return
        }
        beginSignIn(Credentials(username: username, password: password), remember: remember)
    }

    private func beginSignIn(_ value: Credentials, remember: Bool?) {
        beginOperation { [weak self] id in
            guard let self else { return }
            let acquired = try await auth.signIn(value)
            try Task.checkCancellation()
            guard generation == id else { return }
            if let remember {
                if remember { try credentials.save(value) }
                else { try credentials.clear() }
            }
            token = acquired
            isSignedIn = true
            isDemo = false
            let result = try await campus.fetch(token: acquired)
            try Task.checkCancellation()
            guard generation == id else { return }
            try accept(result)
        }
    }

    func enterDemo() {
        stopOperation()
        token = nil
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
        if let token {
            beginOperation { [weak self] id in
                guard let self else { return }
                let result = try await campus.fetch(token: token)
                try Task.checkCancellation()
                guard generation == id else { return }
                try accept(result)
            }
        } else {
            do {
                if let saved = try credentials.load() { beginSignIn(saved, remember: nil) }
                else { isSignedIn = false }
            } catch { report(error) }
        }
    }

    func refreshAndWait() async {
        refresh()
        await operation?.value
    }

    /// Re-evaluate vacancy each minute; the reservation fetch time stays honest.
    func tick() {
        let oldDay = CampusClock.dayKey(now)
        now = Date()
        guard isSignedIn else { return }
        if isDemo && oldDay != CampusClock.dayKey(now) { snapshot = makeDemo() }
        else if !isDemo && !hasTodayData && !isLoading { refresh() }
    }

    func signOut() {
        stopOperation()
        // Demo data never uses the credential store or persistent schedule.
        // Exiting it must work even when Keychain access is unavailable.
        if !isDemo {
            do {
                try credentials.clear()
                try cache.clear()
            } catch { report(error); return }
        }
        token = nil
        snapshot = nil
        isDemo = false
        isSignedIn = false
        errorMessage = nil
    }

    private func accept(_ value: ScheduleSnapshot) throws {
        try cache.save(value)
        snapshot = value
        now = Date()
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
                if let failure = error as? ViewerError,
                   case .invalidCredentials = failure { token = nil; isSignedIn = false }
                report(error)
            }
            guard let self, generation == id else { return }
            isLoading = false
            operation = nil
        }
    }

    private func report(_ error: Error) {
        if let error = error as? URLError {
            errorMessage = error.code == .timedOut ? ViewerError.timeout.localizedDescription
                : "通信できませんでした。MAINS-Xまたは大学VPNへの接続を確認してください。"
        } else { errorMessage = error.localizedDescription }
    }

    private static func resource<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw ViewerError.layoutChanged
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}
