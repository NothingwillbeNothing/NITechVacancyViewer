import Foundation

struct AuthenticationService {
    func signIn(_ credentials: Credentials) async throws -> String {
        let url = URL(string: "https://slb4oam.ict.nitech.ac.jp/openam/json/authenticate?authIndexType=service&authIndexValue=mfaService")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120 // Allow time for the university MFA prompt.
        request.setValue(credentials.username, forHTTPHeaderField: "X-OpenAM-Username")
        request.setValue(credentials.password, forHTTPHeaderField: "X-OpenAM-Password")
        request.setValue("true", forHTTPHeaderField: "X-NoSession")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: SameHostRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ViewerError.authenticationResponse }
        if response.statusCode == 401 || response.statusCode == 403 { throw ViewerError.invalidCredentials }
        guard (200...299).contains(response.statusCode) else { throw ViewerError.http(response.statusCode) }
        struct TokenResponse: Decodable { let tokenId: String? }
        let value = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let token = value.tokenId, !token.isEmpty else { throw ViewerError.authenticationResponse }
        return token
    }
}

/// Do not forward credential headers if an authentication endpoint redirects.
private final class SameHostRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
