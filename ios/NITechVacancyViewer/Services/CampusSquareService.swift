import Foundation
import WebKit

/// Runs the same authenticated Campus Square navigation as the Android WebView.
/// A retained, offscreen WKWebView loads the real page and executes its scripts.
@MainActor
final class CampusSquareService: NSObject, WKNavigationDelegate {
    private let host = "rpxkyomu.ict.nitech.ac.jp"
    private let mainURL = URL(string: "https://rpxkyomu.ict.nitech.ac.jp/campusweb/campussmart.do?page=main")!
    private let flowURL = URL(string: "https://rpxkyomu.ict.nitech.ac.jp/campusweb/campussquare.do?_flowId=KHW0001300-flow")!
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ScheduleSnapshot, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var stage = 0
    private var navigationCount = 0
    private var extractionInProgress = false
    private var requestID = UUID()

    func fetch(token: String) async throws -> ScheduleSnapshot {
        cancel()
        let id = UUID()
        requestID = id
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        webView = view
        stage = 0
        navigationCount = 0
        let cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .name: "sso4cookie", .value: token, .domain: host, .path: "/", .secure: "TRUE"
        ]
        guard let cookie = HTTPCookie(properties: cookieProperties) else { throw ViewerError.authenticationResponse }
        await view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        try Task.checkCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                    catch { return }
                    self?.finish(.failure(ViewerError.timeout))
                }
                view.load(URLRequest(url: mainURL))
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, self.requestID == id else { return }
                self.cancel()
            }
        })
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func finish(_ result: Result<ScheduleSnapshot, Error>) {
        let pending = continuation
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        extractionInProgress = false
        pending?.resume(with: result)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, url.scheme == "https", url.host == host else {
            decisionHandler(.cancel)
            if action.targetFrame?.isMainFrame != false {
                finish(.failure(ViewerError.untrustedNavigation))
            }
            return
        }
        if action.targetFrame?.isMainFrame != false { navigationCount += 1 }
        guard navigationCount < 20 else {
            decisionHandler(.cancel)
            finish(.failure(ViewerError.authenticationResponse))
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            decisionHandler(.cancel)
            finish(.failure(ViewerError.http(http.statusCode)))
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil, !extractionInProgress else { return }
        guard let url = webView.url, url.host == host else {
            finish(.failure(ViewerError.untrustedNavigation))
            return
        }
        if stage == 0 {
            stage = 1
            webView.load(URLRequest(url: flowURL))
            return
        }
        extractionInProgress = true
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let script = "Array.from(document.querySelectorAll('a[href]')).find(a => a.textContent.trim() === '週表示')?.href || ''"
                let week = try await webView.evaluateJavaScript(script) as? String ?? ""
                guard self.webView === webView, self.continuation != nil else { return }
                if !week.isEmpty && self.stage == 1 {
                    guard let weekURL = URL(string: week), weekURL.scheme == "https", weekURL.host == self.host else {
                        throw ViewerError.untrustedNavigation
                    }
                    self.stage = 2
                    self.extractionInProgress = false
                    webView.load(URLRequest(url: weekURL))
                    return
                }
                guard let scriptURL = Bundle.main.url(forResource: "extract-schedule", withExtension: "js") else {
                    throw ViewerError.layoutChanged
                }
                let extraction = try String(contentsOf: scriptURL, encoding: .utf8)
                guard let json = try await webView.evaluateJavaScript(extraction) as? String else {
                    throw ViewerError.layoutChanged
                }
                guard self.webView === webView, self.continuation != nil else { return }
                let snapshot = try ScheduleDecoder.decode(json)
                guard snapshot.rooms(on: Date()) != nil else { throw ViewerError.layoutChanged }
                self.finish(.success(snapshot))
            } catch {
                guard self.webView === webView else { return }
                self.finish(.failure(error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(ViewerError.layoutChanged))
    }
}
