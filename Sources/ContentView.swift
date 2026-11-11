import LocalAuthentication
import SwiftUI

struct ContentView: View {
    private static let defaultHome = "start"

    @StateObject private var model = BrowserModel()

    @AppStorage("browser.homeURL") private var home = ContentView.defaultHome
    @AppStorage("browser.adblock") private var adblock = true
    @AppStorage("browser.hoverPreview") private var hoverPreview = true
    @AppStorage("browser.incognito") private var incognito = true
    @AppStorage("security.lock") private var appLock = false

    @State private var showSettings = false
    @State private var address = ""
    @State private var resetID = 0
    @State private var locked = false
    @Environment(\.scenePhase) private var scenePhase

    private var viewIdentity: String {
        "\(resetID)-\(adblock)-\(hoverPreview)-\(incognito)"
    }

    var body: some View {
        WebView(
            model: model,
            home: home,
            adsBlocked: adblock,
            hoverPreview: hoverPreview,
            incognito: incognito
        )
        .id(viewIdentity)
        .ignoresSafeArea()
        .safeAreaInset(edge: .top) { addressBar }
        .safeAreaInset(edge: .bottom) { toolbar }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                home: $home,
                adblock: $adblock,
                hoverPreview: $hoverPreview,
                incognito: $incognito,
                appLock: $appLock
            )
        }
        .overlay { privacyOverlay }
        .onAppear {
            if appLock {
                locked = true
                authenticate()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background && appLock {
                locked = true
            }
            if phase == .active && locked {
                authenticate()
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("ابحث أو أدخل رابطاً", text: $address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit {
                    model.open(address)
                    address = ""
                }
            if !address.isEmpty {
                Button {
                    address = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar, ignoresSafeAreaEdges: .top)
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            Button {
                model.webView?.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack)

            Button {
                model.webView?.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward)

            Button {
                if model.isLoading {
                    model.webView?.stopLoading()
                } else {
                    model.webView?.reload()
                }
            } label: {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }

            Spacer()

            Button {
                model.loadHome(home)
            } label: {
                Image(systemName: "house")
            }

            Button {
                panic()
            } label: {
                Image(systemName: "eraser.fill")
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        .font(.title3)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.bar, ignoresSafeAreaEdges: .bottom)
    }

    /// زر الذعر: يعيد إنشاء المتصفح بحالة نظيفة فوراً (ومع التخفي يمسح كل شيء)
    private func panic() {
        address = ""
        resetID += 1
    }

    @ViewBuilder
    private var privacyOverlay: some View {
        if locked || scenePhase != .active {
            ZStack {
                Color.black.ignoresSafeArea()
                if locked && scenePhase == .active {
                    Button {
                        authenticate()
                    } label: {
                        Label("افتح القفل", systemImage: "lock.fill")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: .capsule)
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "افتح المتصفح") { success, _ in
            DispatchQueue.main.async {
                locked = !success
            }
        }
    }
}
