import Foundation
import WebKit
import Combine

/// Uses the university's current portal and its actual browser authentication.
/// No OpenAM token is fabricated or forwarded to Microsoft's application proxy.
@MainActor
final class CampusSquareService: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var webView: WKWebView?
    @Published private(set) var showsLogin = false
    @Published private(set) var loginMessage = "大学の画面でログインしてください。"
    @Published private(set) var currentHost = PortalConfiguration.host
    @Published private(set) var sessionWarning: String?
    private var activeNavigation: WKNavigation?
    private var continuation: CheckedContinuation<ScheduleSnapshot, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var requestID = UUID()
    private var dataStore = WKWebsiteDataStore.default()
    private var stage: ConnectionStage = .campusMenu
    private var attemptedFacility = false
    private var followedWeek = false
    private var extractionInProgress = false
    private var navigationCount = 0
    private let session = CampusSessionPersistence()
    private var remembersSession = true
    private var interactiveLogin = false
    private var requiresReauthentication = false

    func configureSession(remember: Bool) async throws {
        cancel()
        session.stop()
        if !remember {
            try session.clear()
            // Opting out also removes cookies left by an earlier remembered login.
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
            )
        }
        remembersSession = remember
        dataStore = remember ? .default() : .nonPersistent()
        sessionWarning = nil
        session.onFailure = { [weak self] error in self?.sessionWarning = error.localizedDescription }
    }

    func fetch(interactive: Bool) async throws -> ScheduleSnapshot {
        cancel()
        let id = UUID()
        requestID = id
        if remembersSession {
            if interactive { session.observe(dataStore.httpCookieStore) }
            else { try await session.restore(into: dataStore.httpCookieStore) }
        }
        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        webView = view
        stage = .campusMenu
        attemptedFacility = false
        followedWeek = false
        extractionInProgress = false
        navigationCount = 0
        interactiveLogin = interactive
        requiresReauthentication = false
        showsLogin = interactive
        loginMessage = "大学の画面でログインしてください。認証後に予約状況を読み込みます。"
        currentHost = PortalConfiguration.host
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 300_000_000_000) }
                    catch { return }
                    guard let self else { return }
                    self.finish(.failure(NetworkFailure(URLError(.timedOut), stage: self.stage, host: self.currentHost)))
                }
                activeNavigation = view.load(URLRequest(url: PortalConfiguration.mainURL))
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, self.requestID == id else { return }
                self.cancel()
            }
        })
    }

    func cancel() {
        requestID = UUID()
        finish(.failure(requiresReauthentication ? ViewerError.sessionExpired : CancellationError()))
    }

    func clearSession() async throws {
        cancel()
        // Stop pending observer saves before deleting the archive and WebKit data.
        var storageError: Error?
        do { try session.clear() }
        catch { storageError = error }
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        if !dataStore.isPersistent {
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
            )
        }
        dataStore = .default()
        sessionWarning = nil
        if let storageError { throw storageError }
    }

    func invalidateSavedSession() throws {
        try session.clear()
    }

    private func requestLogin() {
        if !interactiveLogin {
            requiresReauthentication = true
            loginMessage = ViewerError.sessionExpired.localizedDescription
        }
        showsLogin = true
    }

    func saveSessionBeforeBackgrounding() async {
        guard remembersSession else { return }
        // Only an already verified session should be saved during a login attempt.
        do { try await session.saveIfConfirmed() }
        catch is CancellationError { }
        catch { sessionWarning = error.localizedDescription }
    }

    private func finish(_ result: Result<ScheduleSnapshot, Error>) {
        let pending = continuation
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.stopLoading()
        webView = nil
        activeNavigation = nil
        showsLogin = false
        extractionInProgress = false
        pending?.resume(with: result)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let isMain = action.targetFrame?.isMainFrame != false
        // Application-proxy pages can still contain absolute legacy links.
        if isMain, url.host == PortalConfiguration.legacyHost,
           url.path.hasPrefix("/campusweb"), let translated = PortalConfiguration.campusURL(url) {
            decisionHandler(.cancel)
            activeNavigation = webView.load(URLRequest(url: translated))
            return
        }
        guard PortalConfiguration.isAllowedNavigation(url) else {
            decisionHandler(.cancel)
            if isMain { finish(.failure(ViewerError.untrustedNavigation)) }
            return
        }
        if isMain {
            navigationCount += 1
            currentHost = url.host ?? PortalConfiguration.host
            if url.host != PortalConfiguration.host {
                stage = .authentication
                if interactiveLogin {
                    showsLogin = true
                    loginMessage = "大学・Microsoftの画面で認証を完了してください。"
                }
            }
        }
        guard navigationCount < 60 else {
            decisionHandler(.cancel)
            finish(.failure(ViewerError.authenticationResponse))
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse,
           !(200...399).contains(http.statusCode), response.response.url?.host == PortalConfiguration.host {
            decisionHandler(.cancel)
            finish(.failure(http.statusCode == 401 ? ViewerError.sessionExpired : ViewerError.http(http.statusCode)))
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil, !extractionInProgress else { return }
        if let navigation, let activeNavigation, navigation !== activeNavigation { return }
        guard let url = webView.url else { return }
        currentHost = url.host ?? PortalConfiguration.host
        guard url.host == PortalConfiguration.host else {
            // Keep the browser alive: SSO may still complete without user input.
            requestLogin()
            return // Wait for the actual university/Microsoft login redirect.
        }
        extractionInProgress = true
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let probe = """
                JSON.stringify({
                  tables: document.querySelectorAll('.kyuko-shisetsu-nofixed').length,
                  login: !!document.querySelector('input[type="password"]'),
                  week: Array.from(document.querySelectorAll('a[href]')).find(a => a.textContent.trim() === '週表示')?.href || '',
                  facility: Array.from(document.querySelectorAll('a[href]')).find(a => /KHW0001300-flow|施設利用状況/.test(a.href + ' ' + a.textContent))?.href || ''
                })
                """
                guard let json = try await webView.evaluateJavaScript(probe) as? String,
                      let data = json.data(using: .utf8) else { throw ViewerError.layoutChanged }
                struct Page: Decodable { let tables: Int; let login: Bool; let week: String; let facility: String }
                let page = try JSONDecoder().decode(Page.self, from: data)
                guard self.webView === webView, self.continuation != nil else { return }
                if page.login {
                    extractionInProgress = false
                    if interactiveLogin {
                        showsLogin = true
                        loginMessage = "大学の画面で再度ログインしてください。"
                    } else { requestLogin() }
                    return
                }
                if !page.week.isEmpty && !followedWeek {
                    guard let link = URL(string: page.week), let target = PortalConfiguration.campusURL(link) else {
                        throw ViewerError.untrustedNavigation
                    }
                    followedWeek = true
                    stage = .week
                    extractionInProgress = false
                    activeNavigation = webView.load(URLRequest(url: target))
                    return
                }
                if page.tables > 0 {
                    guard let scriptURL = Bundle.main.url(forResource: "extract-schedule", withExtension: "js") else {
                        throw ViewerError.layoutChanged
                    }
                    let script = try String(contentsOf: scriptURL, encoding: .utf8)
                    guard let payload = try await webView.evaluateJavaScript(script) as? String else {
                        throw ViewerError.layoutChanged
                    }
                    guard self.webView === webView, self.continuation != nil else { return }
                    let snapshot = try ScheduleDecoder.decode(payload)
                    guard snapshot.rooms(on: Date()) != nil else { throw ViewerError.layoutChanged }
                    if remembersSession {
                        do { try await session.saveConfirmedSession() }
                        catch is CancellationError { throw CancellationError() }
                        catch { sessionWarning = error.localizedDescription }
                    }
                    guard self.webView === webView, self.continuation != nil else { return }
                    finish(.success(snapshot))
                    return
                }
                let isPortalMenu = url.path.hasSuffix("campusportal.do")
                    && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: {
                        $0.name == "page" && $0.value == "main"
                    }) == true
                if !attemptedFacility && (isPortalMenu || !page.facility.isEmpty) {
                    attemptedFacility = true
                    stage = .facilities
                    let link = URL(string: page.facility).flatMap { PortalConfiguration.campusURL($0) }
                    extractionInProgress = false
                    activeNavigation = webView.load(URLRequest(url: link ?? PortalConfiguration.facilityURL))
                    return
                }
                // The new portal may use a different menu. Leave it interactive
                // so the user can choose the actual facility reservation page.
                showsLogin = true
                loginMessage = requiresReauthentication ? ViewerError.sessionExpired.localizedDescription
                    : "大学の画面から「施設利用状況参照」を開いてください。予約表を読み取るとアプリに戻ります。"
                extractionInProgress = false
            } catch {
                guard self.webView === webView else { return }
                finish(.failure(error))
            }
        }
    }

    private func handleNavigationFailure(_ view: WKWebView, navigation: WKNavigation?, error: Error) {
        guard webView === view, continuation != nil else { return }
        if NetworkFailure.isCancelledNavigation(error) { return }
        if let navigation, let activeNavigation, navigation !== activeNavigation { return }
        finish(.failure(NetworkFailure(error, stage: stage, host: currentHost)))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(webView, navigation: navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(webView, navigation: navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(ViewerError.layoutChanged))
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, let url = action.request.url,
           PortalConfiguration.isAllowedNavigation(url) {
            activeNavigation = webView.load(action.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        loginMessage = message
        showsLogin = true
        completionHandler()
    }
}
