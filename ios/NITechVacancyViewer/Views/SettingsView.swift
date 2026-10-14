import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("appearance") private var appearance = "system"
    @State private var confirmSignOut = false
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "1.0") (\(info["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        Form {
            Section("全般") {
                SessionStorageWarning(service: store.campus)
                Picker("テーマ", selection: $appearance) {
                    Text("システム設定").tag("system")
                    Text("ライト").tag("light")
                    Text("ダーク").tag("dark")
                }
                Button("OSのアプリ設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Section("アプリについて") {
                LabeledContent("バージョン", value: version)
                Link("元のAndroidアプリ", destination: URL(string: "https://github.com/Punyo/NITechVacancyViewer")!)
                Link("iOS版ソースコード", destination: URL(string: "https://github.com/NothingwillbeNothing/NITechVacancyViewer")!)
                Link("利用規約", destination: URL(string: "https://punyo.github.io/legal/tos.html")!)
                Link("プライバシーポリシー", destination: URL(string: "https://punyo.github.io/legal/privacypolicy.html")!)
                Text("PunyoのNITechVacancyViewerを基にした非公式iOS版です。大学公式アプリではありません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button(store.isDemo ? "デモを終了" : "ログアウト", role: .destructive) { confirmSignOut = true }
            } footer: {
                Text(store.isDemo ? "デモを終了するとログイン画面に戻ります。" : "ログアウトすると、この端末に保存した認証情報と予約データを削除します。")
            }
        }
        .navigationTitle("設定")
        .confirmationDialog("ログアウトしますか？", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("ログアウト", role: .destructive) { store.signOut() }
            Button("キャンセル", role: .cancel) { }
        }
        .alert("エラー", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK") { store.errorMessage = nil } } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct SessionStorageWarning: View {
    @ObservedObject var service: CampusSquareService

    var body: some View {
        if let warning = service.sessionWarning {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(.red)
        }
    }
}
