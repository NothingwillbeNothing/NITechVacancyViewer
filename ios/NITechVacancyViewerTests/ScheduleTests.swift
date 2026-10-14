import XCTest
#if SWIFT_PACKAGE
@testable import NITechVacancyCore
#endif

final class ScheduleTests: XCTestCase {
    private let event = Reservation(start: 530, end: 620, description: "電気回路Ⅱ")

    func testReservationStartIsOccupiedAndEndIsVacant() {
        let room = Room(name: "0111", events: [event])
        XCTAssertEqual(room.vacancy(at: 529), .vacant)
        XCTAssertEqual(room.vacancy(at: 530), .occupied)
        XCTAssertEqual(room.vacancy(at: 619), .occupied)
        XCTAssertEqual(room.vacancy(at: 620), .vacant)
    }

    func testUnknownTimeDoesNotReportVacant() {
        let unknown = Reservation(start: nil, end: nil, description: "時刻不明")
        let room = Room(name: "0111", events: [unknown, event])
        XCTAssertEqual(room.vacancy(at: 700), .unknown)
        XCTAssertEqual(room.vacancy(at: 550), .occupied)
    }

    func testNextEventUsesEarliestFutureReservation() {
        let room = Room(name: "0111", events: [Reservation(start: 800, end: 850, description: "後"), event])
        XCTAssertEqual(room.nextEvent(at: 500), event)
        XCTAssertEqual(room.nextEvent(at: 700)?.start, 800)
        XCTAssertNil(room.nextEvent(at: 900))
    }

    func testFullWidthWhitespaceAndLongDescription() {
        let parsed = ScheduleDecoder.parseEvent("08:50-10:20　1552_電気回路Ⅱ　担当者 備考")
        XCTAssertEqual(parsed.start, 530)
        XCTAssertEqual(parsed.end, 620)
        XCTAssertEqual(parsed.description, "1552_電気回路Ⅱ　担当者 備考")
    }

    func testUnicodeDashAndOrdinaryWhitespace() {
        let parsed = ScheduleDecoder.parseEvent(" 8:50 – 10:20 講義 ")
        XCTAssertEqual(parsed.start, 530)
        XCTAssertEqual(parsed.description, "講義")
    }

    func testOpenEndedMarkersSpanFullDay() {
        let parsed = ScheduleDecoder.parseEvent("<<->>　終日予約")
        XCTAssertEqual(parsed.start, 0)
        XCTAssertEqual(parsed.end, 1440)
        XCTAssertTrue(parsed.contains(1439))
        XCTAssertEqual(parsed.timeLabel, "00:00 ～ 24:00")
    }

    func testInvalidTimeAndInvertedRangeRemainUnknown() {
        for text in ["26:00-27:00 予約", "10:60-12:00 予約", "12:00-10:00 予約", "12:00-12:00 予約", "時刻不明", "24:00-24:00 予約"] {
            let parsed = ScheduleDecoder.parseEvent(text)
            XCTAssertFalse(parsed.hasKnownTime, text)
            XCTAssertEqual(Room(name: "a", events: [parsed]).vacancy(at: 600), .unknown, text)
        }
    }

    func testCampusDateUsesJapanTimeAndRollsOver() {
        let before = ISO8601DateFormatter().date(from: "2026-12-31T14:59:00Z")!
        let after = ISO8601DateFormatter().date(from: "2026-12-31T15:00:00Z")!
        XCTAssertEqual(CampusClock.dayKey(before), "2026-12-31")
        XCTAssertEqual(CampusClock.dayKey(after), "2027-01-01")
        XCTAssertEqual(CampusClock.minute(after), 0)
    }

    func testDecodeWeekCrossesMonthBoundary() throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-31T03:00:00Z")!
        let json = #"{"days":[{"date":null,"rooms":[{"name":"0111","events":[{"text":"08:50-10:20　講義"}]}]},{"date":null,"rooms":[{"name":"0111","events":[]}]}]}"#
        let decoded = try ScheduleDecoder.decode(json, fetchedAt: date)
        XCTAssertEqual(decoded.days.map(\.date), ["2026-10-31", "2026-11-01"])
        XCTAssertEqual(decoded.days[0].rooms[0].events[0].start, 530)
        XCTAssertEqual(decoded.days[1].rooms[0].vacancy(at: 600), .vacant)
        XCTAssertNil(decoded.rooms(on: CampusClock.addingDays(2, to: date)))
    }

    func testDecodeRejectsMissingOrDuplicateRows() {
        for json in [#"{"days":[]}"#, #"{"days":[{"date":"2026-02-30","rooms":[{"name":"a","events":[]}]}]}"#, #"{"days":[{"rooms":[]}]}"#, #"{"days":[{"rooms":[{"name":"a","events":[]},{"name":"a","events":[]}]}]}"#] {
            XCTAssertThrowsError(try ScheduleDecoder.decode(json))
        }
    }

    func testSnapshotCacheRoundTrip() throws {
        let date = Date()
        let snapshot = ScheduleSnapshot(fetchedAt: date, days: [DailySchedule(date: CampusClock.dayKey(date), rooms: [Room(name: "a", events: [event])])])
        let decoded = try JSONDecoder().decode(ScheduleSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }

    func testNavigationCancellationIsDistinguishedFromConnectionFailure() {
        XCTAssertTrue(NetworkFailure.isCancelledNavigation(URLError(.cancelled)))
        XCTAssertFalse(NetworkFailure.isCancelledNavigation(URLError(.cannotConnectToHost)))
        XCTAssertFalse(NetworkFailure.isCancelledNavigation(NSError(domain: "Other", code: -999)))
    }

    func testNetworkDiagnosticContainsStageAndCodeWithoutURLQuery() {
        let error = NSError(domain: NSURLErrorDomain, code: -1003, userInfo: [
            NSURLErrorFailingURLStringErrorKey: "https://example.test/?token=private",
            NSLocalizedDescriptionKey: "secret-response"
        ])
        let failure = NetworkFailure(error, stage: .campusMenu, host: "example.test")
        let text = failure.localizedDescription
        XCTAssertTrue(text.contains("Campus Square"))
        XCTAssertTrue(text.contains("-1003"))
        XCTAssertTrue(text.contains("example.test"))
        XCTAssertFalse(text.contains("private"))
        XCTAssertFalse(text.contains("secret-response"))
    }

    func testNestedURLFailureRetainsConnectionCode() {
        let error = NSError(domain: "WebKit", code: 1, userInfo: [
            NSUnderlyingErrorKey: URLError(.secureConnectionFailed)
        ])
        XCTAssertEqual(NetworkFailure(error, stage: .week, host: "example.test").code, -1200)
    }

    func testPortalUsesCurrentCampusAddress() {
        XCTAssertEqual(PortalConfiguration.mainURL.host, "aprkyomu-nitechict.msappproxy.net")
        XCTAssertEqual(PortalConfiguration.mainURL.path, "/campusweb/campusportal.do")
        XCTAssertTrue(PortalConfiguration.mainURL.query?.contains("tabId=kh") == true)
    }

    func testLegacyCampusLinksAreRebasedWithoutChangingFlow() {
        let url = URL(string: "https://rpxkyomu.ict.nitech.ac.jp/campusweb/campussquare.do?flowExecutionKey=e1s2&mode=week")!
        let result = PortalConfiguration.campusURL(url)
        XCTAssertEqual(result?.host, PortalConfiguration.host)
        XCTAssertEqual(result?.path, url.path)
        XCTAssertEqual(result?.query, url.query)
    }

    func testAuthenticationHostAllowlistRejectsLookalikes() {
        for host in [PortalConfiguration.host, "login.microsoftonline.com", "slb4oam.ict.nitech.ac.jp"] {
            XCTAssertTrue(PortalConfiguration.isAllowedNavigation(URL(string: "https://\(host)/")!))
        }
        for host in ["login.microsoftonline.com.evil.test", "other.msappproxy.net", "nitech.ac.jp.evil.test"] {
            XCTAssertFalse(PortalConfiguration.isAllowedNavigation(URL(string: "https://\(host)/")!))
        }
        XCTAssertFalse(PortalConfiguration.isAllowedNavigation(URL(string: "http://login.microsoftonline.com/")!))
    }

    func testAuthenticationURLsAreNotRewrittenToCampusHost() {
        XCTAssertNil(PortalConfiguration.campusURL(URL(string: "https://login.microsoftonline.com/authorize")!))
        XCTAssertNil(PortalConfiguration.campusURL(URL(string: "http://rpxkyomu.ict.nitech.ac.jp/campusweb/")!))
    }
}
