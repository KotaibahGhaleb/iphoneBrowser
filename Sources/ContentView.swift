import SwiftUI
import LocalAuthentication
import WebKit

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @StateObject private var favs = FavoritesStore()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("browser.homeURL") private var home = "start"
    @AppStorage("browser.adblock") private var adblock = true
    @AppStorage("browser.hoverPreview") private var hoverPreview = true
    @AppStorage("browser.incognito") private var incognito = true
    @AppStorage("security.lock") private var appLock = false

    @State private var address = ""
    @State private var showSettings = false
    @State private var locked = false

    private var config: BrowserConfig {
        BrowserConfig(adsBlocked: adblock, hoverPreview: hoverPreview, incognito: incognito)
    }

    /// إعدادات تحتاج إعادة بناء الـ WebView النشط
    private var settingsIdentity: String {
        "\(adblock)-\(hoverPreview)-\(incognito)"
    }

    private var currentURL: URL? { model.activeTab?.url }

    var body: some View {
        Group {
            if let wv = model.webView {
                WebHostView(webView: wv)
            } else {
                Color.black
            }
        }
        .id(model.activeID)
        .ignoresSafeArea()
        .safeAreaInset(edge: .top) { addressBar }
        .safeAreaInset(edge: .bottom) { toolbar }
        .sheet(isPresented: $showSettings) {
            SettingsView(home: $home, adblock: $adblock, hoverPreview: $hoverPreview, incognito: $incognito, appLock: $appLock)
        }
        .sheet(isPresented: $model.showTabSwitcher) {
            TabSwitcherView(model: model, config: config, home: home)
        }
        .overlay {
            if locked || scenePhase != .active {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            model.favorites = favs
            if appLock {
                locked = true
                authenticate()
            }
        }
        .task(id: settingsIdentity) {
            if model.tabs.isEmpty {
                model.ensureTab(config: config, home: home)
            } else {
                model.rebuildActive(config: config, home: home)
            }
        }
        .task {
            await model.fetchFeeds()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && appLock && locked {
                authenticate()
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            TextField("بحث أو رابط…", text: $address)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .onSubmit { model.open(address) }

            if model.isSearching {
                ProgressView().scaleEffect(0.9)
            } else {
                Button { model.open(address) } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Button { model.webView?.goBack() } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!model.canGoBack)

            Button { model.webView?.goForward() } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!model.canGoForward)

            Button { model.webView?.reload() } label: {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }

            Spacer()

            Button {
                if let url = currentURL {
                    favs.toggle(title: model.activeTab?.title, url: url, kind: "fav")
                }
            } label: {
                Image(systemName: favs.isSaved(currentURL?.absoluteString, kind: "fav") ? "heart.fill" : "heart")
            }
            .disabled(currentURL == nil)

            Button {
                if let url = currentURL {
                    favs.toggle(title: model.activeTab?.title, url: url, kind: "later")
                }
            } label: {
                Image(systemName: favs.isSaved(currentURL?.absoluteString, kind: "later") ? "clock.fill" : "clock")
            }
            .disabled(currentURL == nil)

            Button { model.showTabSwitcher = true } label: {
                ZStack {
                    Image(systemName: "square.on.square")
                    if model.tabs.count > 1 {
                        Text("\(model.tabs.count)")
                            .font(.system(size: 9, weight: .bold))
                            .offset(x: 8, y: 6)
                    }
                }
            }

            Button { model.panic(config: config, home: home) } label: {
                Image(systemName: "eraser.fill")
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
        .font(.body)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .background(ignoresSafeAreaEdges: .bottom)
    }

    private func authenticate() {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) {
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "افتح المتصفح") { ok, _ in
                Task { @MainActor in
                    locked = !ok
                }
            }
        } else {
            locked = false
        }
    }
}
