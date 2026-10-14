import SwiftUI

struct DataStatusView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.isDemo {
                Label("デモモード · 実際の予約状況ではありません", systemImage: "play.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let snapshot = store.snapshot, store.hasTodayData {
                Label("予約データ取得：\(CampusClock.timestamp(snapshot.fetchedAt))", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
                Text("空室判定は60秒おきに更新 · 下に引いて予約データを再取得")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if store.isLoading {
                HStack(spacing: 8) { ProgressView(); Text("予約状況を取得しています…").font(.caption) }
            }
            if let message = store.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                    if store.hasTodayData {
                        Text("保存済みの予約データを表示しています。現在の予約と異なる場合があります。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("再試行") { store.refresh() }.disabled(store.isLoading)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VacancyBadge: View {
    let vacancy: Vacancy
    private var title: String {
        switch vacancy { case .vacant: return "空室"; case .occupied: return "使用中"; case .unknown: return "不明" }
    }
    private var color: Color {
        switch vacancy { case .vacant: return .green; case .occupied: return .orange; case .unknown: return .secondary }
    }
    var body: some View {
        Text(title).font(.caption.weight(.semibold))
            .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 48)
    }
}
