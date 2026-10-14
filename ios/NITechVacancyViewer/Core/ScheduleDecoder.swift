import Foundation

/// Decodes the DOM extraction payload. Invalid reservation times stay unknown,
/// so a malformed entry can never turn a reserved room into a vacant room.
enum ScheduleDecoder {
    private struct Payload: Decodable {
        let days: [Day]
        struct Day: Decodable {
            let date: String?
            let rooms: [RawRoom]
        }
        struct RawRoom: Decodable {
            let name: String
            let events: [RawEvent]
        }
        struct RawEvent: Decodable { let text: String }
    }

    static func decode(_ json: String, fetchedAt: Date = Date()) throws -> ScheduleSnapshot {
        guard let data = json.data(using: .utf8) else { throw ViewerError.layoutChanged }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.days.isEmpty, payload.days.count <= 7 else { throw ViewerError.layoutChanged }
        var seenDates = Set<String>()
        let days = try payload.days.enumerated().map { offset, day -> DailySchedule in
            let key = day.date ?? CampusClock.dayKey(CampusClock.addingDays(offset, to: fetchedAt))
            guard validDay(key), seenDates.insert(key).inserted, !day.rooms.isEmpty else {
                throw ViewerError.layoutChanged
            }
            var names = Set<String>()
            let rooms = try day.rooms.map { raw -> Room in
                let name = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, names.insert(name).inserted else { throw ViewerError.layoutChanged }
                return Room(name: name, events: raw.events.map { parseEvent($0.text) })
            }
            return DailySchedule(date: key, rooms: rooms)
        }
        return ScheduleSnapshot(fetchedAt: fetchedAt, days: days)
    }

    static func parseEvent(_ text: String) -> Reservation {
        // The Android parser splits on an ideographic space. Retain the entire
        // description and also tolerate ordinary whitespace and Unicode dashes.
        let pattern = #"^\s*(<<|\d{1,2}:\d{2})\s*[-－–—]\s*(>>|\d{1,2}:\d{2})\s*(.*)$"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return Reservation(start: nil, end: nil, description: text)
        }
        let start = parseMinute(ns.substring(with: match.range(at: 1)))
        let end = parseMinute(ns.substring(with: match.range(at: 2)))
        let description = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
        let event = Reservation(start: start, end: end, description: description)
        guard event.hasKnownTime else {
            return Reservation(start: nil, end: nil, description: description.isEmpty ? text : description)
        }
        return event
    }

    private static func parseMinute(_ text: String) -> Int? {
        if text == "<<" { return 0 }
        if text == ">>" { return 1440 }
        let values = text.split(separator: ":").compactMap { Int($0) }
        guard values.count == 2, (0...24).contains(values[0]), (0...59).contains(values[1]),
              values[0] < 24 || values[1] == 0 else { return nil }
        return values[0] * 60 + values[1]
    }

    private static func validDay(_ key: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = CampusClock.calendar
        formatter.timeZone = CampusClock.calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: key) else { return false }
        return formatter.string(from: date) == key
    }
}
