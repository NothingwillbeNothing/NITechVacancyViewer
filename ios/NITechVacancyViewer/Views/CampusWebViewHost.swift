import SwiftUI
import WebKit

struct CampusWebViewHost: UIViewRepresentable {
    @ObservedObject var service: CampusSquareService

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let webView = service.webView else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}

struct CampusSessionPresenter: View {
    @ObservedObject var service: CampusSquareService

    var body: some View {
        ZStack {
            Color.clear.frame(width: 1, height: 1)
            if !service.showsLogin {
                CampusWebViewHost(service: service)
                    .frame(width: 320, height: 480)
                    .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .sheet(isPresented: Binding(
            get: { service.showsLogin },
            set: { if !$0 && service.showsLogin { service.cancel() } }
        )) {
            NavigationStack {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(service.loginMessage).font(.caption)
                        Text(service.currentHost).font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    Divider()
                    CampusWebViewHost(service: service)
                }
                .navigationTitle("大学アカウント")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("閉じる") { service.cancel() }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}
