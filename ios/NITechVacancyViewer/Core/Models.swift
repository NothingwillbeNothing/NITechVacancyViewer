import Foundation

enum CampusClock {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }

    static func dayKey(_ date: Date = Date()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func minute(_ date: Date = Date()) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }

    static func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    static func timeLabel(_ minute: Int?) -> String {
        guard let minute else { return "不明" }
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

struct Reservation: Codable, Equatable {
    let start: Int?
    let end: Int?
    let description: String

    var hasKnownTime: Bool {
        guard let start, let end else { return false }
        return (0...1439).contains(start) && (1...1440).contains(end) && start < end
    }

    func contains(_ minute: Int) -> Bool {
        guard hasKnownTime, let start, let end else { return false }
        return start <= minute && minute < end
    }

    var timeLabel: String { "\(CampusClock.timeLabel(start)) ～ \(CampusClock.timeLabel(end))" }
}

enum Vacancy: Equatable {
    case vacant
    case occupied
    case unknown
}

struct Room: Codable, Identifiable, Equatable {
    let name: String
    let events: [Reservation]
    var id: String { name }

    func vacancy(at minute: Int) -> Vacancy {
        if events.contains(where: { $0.contains(minute) }) { return .occupied }
        if events.contains(where: { !$0.hasKnownTime }) { return .unknown }
        return .vacant
    }

    func currentEvent(at minute: Int) -> Reservation? {
        events.first(where: { $0.contains(minute) })
    }

    func nextEvent(at minute: Int) -> Reservation? {
        events.filter { $0.hasKnownTime && ($0.start ?? -1) > minute }
            .min { ($0.start ?? 0) < ($1.start ?? 0) }
    }
}

struct Building: Codable, Identifiable, Hashable {
    let name: String
    let image: String
    let rooms: [String]
    var id: String { name }
}

struct DailySchedule: Codable, Equatable {
    let date: String
    let rooms: [Room]
}

struct ScheduleSnapshot: Codable, Equatable {
    let fetchedAt: Date
    let days: [DailySchedule]

    func rooms(on date: Date) -> [Room]? {
        days.first { $0.date == CampusClock.dayKey(date) }?.rooms
    }
}

struct Credentials: Codable {
    let username: String
    let password: String
}

enum ViewerError: LocalizedError {
    case invalidCredentials
    case authenticationResponse
    case http(Int)
    case layoutChanged
    case untrustedNavigation
    case timeout
    case credentialStorage(Int32)
    case sessionStorage
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "ログインが拒否されました。基盤ID・パスワードと認証要求を確認してください。"
        case .authenticationResponse:
            return "認証を完了できませんでした。認証要求を確認して再試行してください。"
        case .http(let code):
            return "サーバーからエラーが返されました（\(code)）。時間をおいて再試行してください。"
        case .layoutChanged:
            return "予約表を読み取れませんでした。Campus Squareの表示形式を確認してください。"
        case .untrustedNavigation:
            return "Campus Squareから別のサイトに移動しました。再度ログインしてください。"
        case .timeout:
            return "通信がタイムアウトしました。MAINS-Xまたは大学VPNへの接続を確認してください。"
        case .credentialStorage:
            return "認証情報をキーチェーンに保存できませんでした。"
        case .sessionStorage:
            return "保存したログイン情報を読み込めませんでした。再度ログインしてください。"
        case .sessionExpired:
            return "ログインの有効期限が切れました。大学アカウントで再度ログインしてください。"
        }
    }
}
