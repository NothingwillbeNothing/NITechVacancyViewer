import SwiftUI

struct BuildingsView: View {
    @EnvironmentObject private var store: AppStore
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DataStatusView()
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.buildings) { building in
                        NavigationLink(value: building) { buildingCard(building) }
                            .buttonStyle(.plain)
                    }
                }
            }.padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("NITechSearch")
        .navigationDestination(for: Building.self) { BuildingRoomsView(building: $0) }
        .refreshable { await store.refreshAndWait() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.isLoading).accessibilityLabel("予約データを更新")
            }
        }
    }

    private func buildingCard(_ building: Building) -> some View {
        let vacant = building.rooms.compactMap { store.room(named: $0) }
            .filter { $0.vacancy(at: store.minute) == .vacant }.count
        let unknown = building.rooms.filter {
            guard let room = store.room(named: $0) else { return true }
            return room.vacancy(at: store.minute) == .unknown
        }.count
        return VStack(alignment: .leading, spacing: 0) {
            Image(building.image).resizable().scaledToFill().frame(height: 112).clipped()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(building.name).font(.headline)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                Text("空室：\(vacant) / \(building.rooms.count) 部屋")
                    .font(.subheadline).foregroundStyle(Color("AccentColor"))
                if unknown > 0 { Text("\(unknown)部屋は情報なし").font(.caption).foregroundStyle(.secondary) }
            }.padding(14)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct BuildingRoomsView: View {
    @EnvironmentObject private var store: AppStore
    let building: Building

    var body: some View {
        List {
            Section { DataStatusView() }
            Section("講義室") {
                ForEach(building.rooms, id: \.self) { name in
                    NavigationLink { RoomDetailView(name: name) } label: { RoomRow(name: name) }
                }
            }
        }
        .navigationTitle(building.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshAndWait() }
    }
}

struct RoomRow: View {
    @EnvironmentObject private var store: AppStore
    let name: String

    var body: some View {
        let room = store.room(named: name)
        let vacancy = room?.vacancy(at: store.minute) ?? .unknown
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.headline)
                if let current = room?.currentEvent(at: store.minute) {
                    Text(current.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(current.timeLabel).font(.caption2).foregroundStyle(.secondary)
                } else if let room {
                    Text(room.events.isEmpty ? "予約なし" : "\(room.events.count)件の予約")
                        .font(.caption).foregroundStyle(.secondary)
                    if let next = room.nextEvent(at: store.minute), let start = next.start {
                        Text("次の予約まで\(start - store.minute)分")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("今日の予約データがありません").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VacancyBadge(vacancy: vacancy)
        }.padding(.vertical, 5)
    }
}
