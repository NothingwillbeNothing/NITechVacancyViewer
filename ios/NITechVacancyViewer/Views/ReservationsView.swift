import SwiftUI

struct ReservationsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var vacantOnly = false

    private var filtered: [Room] {
        store.rooms.filter {
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) &&
            (!vacantOnly || $0.vacancy(at: store.minute) == .vacant)
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section { DataStatusView(); Toggle("空室だけ表示", isOn: $vacantOnly) }
            Section {
                if filtered.isEmpty {
                    EmptyStateView(title: store.hasTodayData ? "該当する講義室がありません" : "今日の予約データがありません", systemImage: "calendar")
                } else {
                    ForEach(filtered) { room in
                        NavigationLink { RoomDetailView(name: room.name) } label: { RoomRow(name: room.name) }
                    }
                }
            }
        }
        .navigationTitle("今日の予約")
        .searchable(text: $search, prompt: "講義室番号で検索")
        .refreshable { await store.refreshAndWait() }
    }
}

struct RoomDetailView: View {
    @EnvironmentObject private var store: AppStore
    let name: String

    var body: some View {
        let room = store.room(named: name)
        List {
            Section { DataStatusView(); RoomRow(name: name) }
            Section("今日の予約") {
                if let room, !room.events.isEmpty {
                    ForEach(Array(room.events.enumerated()), id: \.offset) { _, event in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.description.isEmpty ? "施設予約" : event.description).font(.headline)
                            Label(event.timeLabel, systemImage: "clock")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if !event.hasKnownTime {
                                Text("時刻が不明なため、空室と判定できません。")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }.padding(.vertical, 4)
                    }
                } else {
                    EmptyStateView(title: room == nil ? "予約データがありません" : "予約がありません", systemImage: "calendar.badge.checkmark")
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshAndWait() }
    }
}
