import Foundation

enum ConnectionStage: String {
    case authentication = "基盤IDの認証"
    case campusMenu = "Campus Squareのメニュー"
    case facilities = "施設利用状況"
    case week = "週表示の予約表"
}

/// Keeps the failing stage and framework error code without exposing a URL's
/// query, cookies, response body, username, or password.
struct NetworkFailure: LocalizedError {
    let stage: ConnectionStage
    let host: String
    let domain: String
    let code: Int

    init(_ error: Error, stage: ConnectionStage, host: String) {
        var value = error as NSError
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSURLErrorDomain { value = underlying }
        self.stage = stage
        self.host = host
        self.domain = value.domain
        self.code = value.code
    }

    static func isCancelledNavigation(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == NSURLErrorDomain && value.code == URLError.cancelled.rawValue
    }

    var errorDescription: String? {
        let reason: String
        if domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: code) {
            case .timedOut:
                reason = "サーバーが応答しませんでした。時間をおいて再試行してください。"
            case .cannotFindHost, .dnsLookupFailed:
                reason = "大学サーバーの名前を解決できませんでした。学内接続とDNSを確認してください。"
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                reason = "学内接続と、このアプリのローカルネットワーク許可を確認してください。"
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                reason = "大学サーバーとのTLS接続または証明書の確認に失敗しました。"
            case .appTransportSecurityRequiresSecureConnection:
                reason = "接続先がiOSの安全な通信条件を満たしていません。"
            default:
                reason = "通信処理に失敗しました。下の詳細コードを確認してください。"
            }
        } else {
            reason = "ページの読み込みに失敗しました。下の詳細コードを確認してください。"
        }
        return "\(stage.rawValue)を読み込めませんでした。\n\(reason)\n詳細：\(domain) \(code)\n接続先：\(host)"
    }
}
