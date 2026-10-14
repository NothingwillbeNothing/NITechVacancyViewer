import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var store: AppStore
    @State private var username = ""
    @State private var password = ""
    @State private var remember = true
    @FocusState private var focus: Field?
    private enum Field: Hashable { case username, password }

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

                    VStack(alignment: .leading, spacing: 16) {
                        TextField("基盤ID（@ict.nitech.ac.jpなし）", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .submitLabel(.next)
                            .focused($focus, equals: .username)
                            .onSubmit { focus = .password }
                        SecureField("パスワード", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focus, equals: .password)
                            .onSubmit { login() }
                        Toggle("認証情報をこの端末に保存", isOn: $remember)
                            .font(.subheadline)
                    }
                    .textFieldStyle(.roundedBorder)
                    .disabled(store.isLoading)

                    if let message = store.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.red)
                            .accessibilityIdentifier("signInError")
                    }

                    Button(action: login) {
                        HStack {
                            if store.isLoading { ProgressView().tint(.white) }
                            Text(store.isLoading ? "ログインしています…" : "ログイン")
                                .fontWeight(.semibold)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isLoading || username.isEmpty || password.isEmpty)
                    .accessibilityIdentifier("signInButton")

                    Text("MAINS-X、または大学VPNへの接続が必要です。認証要求が届いた場合は承認してください。")
                        .font(.footnote).foregroundStyle(.secondary)

                    Button("デモを試す") { focus = nil; password = ""; store.enterDemo() }
                        .frame(maxWidth: .infinity).buttonStyle(.bordered)
                        .disabled(store.isLoading)
                        .accessibilityIdentifier("demoButton")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ログイン前に元のアプリの利用規約とプライバシーポリシーを確認してください。")
                        HStack {
                            Link("利用規約", destination: URL(string: "https://punyo.github.io/legal/tos.html")!)
                            Text("・")
                            Link("プライバシーポリシー", destination: URL(string: "https://punyo.github.io/legal/privacypolicy.html")!)
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                .padding(24).frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }
    }

    private func login() {
        guard !store.isLoading else { return }
        focus = nil
        store.signIn(username: username, password: password, remember: remember)
    }
}
