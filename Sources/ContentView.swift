import Network
import SwiftUI

struct ContentView: View {
    private static let defaultHome = "https://viralxxxporn.com/"

    @StateObject private var model = BrowserModel()
    @StateObject private var proxy = ProxyController()

    @AppStorage("browser.homeURL") private var home = ContentView.defaultHome
    @AppStorage("proxy.mode") private var modeRaw = ProxyMode.auto.rawValue
    @AppStorage("proxy.type") private var proxyType = ManualProxyType.socks5.rawValue
    @AppStorage("proxy.host") private var proxyHost = ""
    @AppStorage("proxy.port") private var proxyPort = 1080
    @AppStorage("proxy.user") private var proxyUser = ""
    @AppStorage("proxy.pass") private var proxyPass = ""
    @AppStorage("browser.adblock") private var adblock = true

    @State private var showSettings = false

    private var mode: ProxyMode {
        ProxyMode(rawValue: modeRaw) ?? .auto
    }

    private var homeURL: URL {
        URL(string: home) ?? URL(string: ContentView.defaultHome)!
    }

    private var manualConfig: ProxyConfiguration? {
        ProxyController.manual(
            type: ManualProxyType(rawValue: proxyType) ?? .socks5,
            host: proxyHost,
            port: proxyPort,
            username: proxyUser,
            password: proxyPass
        )
    }

    private var settingsIdentity: String {
        [modeRaw, proxyType, proxyHost, String(proxyPort), proxyUser, proxyPass, String(adblock)]
            .joined(separator: "|")
    }

    var body: some View {
        WebView(model: model, controller: proxy, homeURL: homeURL, adsBlocked: adblock)
            .id(proxy.revision)
            .ignoresSafeArea(.container, edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if !proxy.status.isEmpty {
                        Text(proxy.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(.bar)
                    }
                    toolbar
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    controller: proxy,
                    modeRaw: $modeRaw,
                    typeRaw: $proxyType,
                    host: $proxyHost,
                    port: $proxyPort,
                    username: $proxyUser,
                    password: $proxyPass,
                    home: $home,
                    adblock: $adblock
                )
            }
            .task(id: settingsIdentity) {
                proxy.configure(mode: mode, manual: manualConfig)
            }
    }

    private var toolbar: some View {
        HStack(spacing: 20) {
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
                model.webView?.load(URLRequest(url: homeURL))
            } label: {
                Image(systemName: "house")
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
        .background(.bar)
    }
}
