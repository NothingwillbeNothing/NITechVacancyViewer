import SwiftUI

@main
@MainActor
struct NITechVacancyViewerApp: App {
    @StateObject private var store = AppStore()
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color("AccentColor"))
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .task { store.start() }
                .onReceive(timer) { _ in if scenePhase == .active { store.tick() } }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { store.tick() }
                    else if phase == .background {
                        Task { await store.saveSessionBeforeBackgrounding() }
                    }
                }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if !store.isReady {
                ProgressView("準備しています…")
            } else if store.isSignedIn {
                TabView {
                    NavigationStack { BuildingsView() }
                        .tabItem { Label("ホーム", systemImage: "building.2") }
                    NavigationStack { ReservationsView() }
                        .tabItem { Label("今日の予約", systemImage: "calendar") }
                    NavigationStack { SettingsView() }
                        .tabItem { Label("設定", systemImage: "gearshape") }
                }
            } else {
                SignInView()
            }
        }
        .overlay(alignment: .topLeading) {
            CampusSessionPresenter(service: store.campus)
        }
    }
}
