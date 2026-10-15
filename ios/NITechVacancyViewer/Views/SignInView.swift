import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var store: AppStore
    @State private var remember = UserDefaults.standard.object(forKey: "rememberCampusSession") as? Bool ?? true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.system(size: 60)).foregroundStyle(Color("AccentColor"))
                        Text("NITechSearch").font(.largeTitle.bold())
                        Text("名工大の空いている講義室を見つけよう。")
                            .font(.title3).foregroundStyle(.secondary)
                    }.padding(.top, 32)

                    Text("大学のログイン画面で認証すると、施設の予約状況を読み込みます。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Toggle("この端末でログイン状態を保持", isOn: $remember)
                        .font(.subheadline).disabled(store.isLoading)
                    Text("ログイン状態を保持すると、次回の起動時に復元します。有効期限が切れた場合は再ログインをご案内します。")
                        .font(.caption).foregroundStyle(.secondary)

                    if let message = store.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.red)
                            .accessibilityIdentifier("signInError")
                    }

                    Button { store.signIn(remember: remember) } label: {
                        HStack {
                            if store.isLoading { ProgressView().tint(.white) }
                            Text(store.isLoading ? "読み込んでいます…" : "大学アカウントでログイン")
                                .fontWeight(.semibold)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent).disabled(store.isLoading)
                    .accessibilityIdentifier("signInButton")

                    Button("デモを試す") { store.enterDemo() }
                        .frame(maxWidth: .infinity).buttonStyle(.bordered)
                        .disabled(store.isLoading).accessibilityIdentifier("demoButton")

                    Text("新しいCampus Squareポータルに対応しています。認証要求が届いた場合は大学の案内に従って承認してください。")
                        .font(.footnote).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ログイン前に元のアプリの利用規約とプライバシーポリシーを確認してください。")
                        HStack {
                            Link("利用規約", destination: URL(string: "https://punyo.github.io/legal/tos.html")!)
                            Text("・")
                            Link("プライバシーポリシー", destination: URL(string: "https://punyo.github.io/legal/privacypolicy.html")!)
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                .padding(24).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
    }
}
