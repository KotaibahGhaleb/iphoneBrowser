import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let model: BrowserModel
    let controller: ProxyController
    let homeURL: URL
    let adsBlocked: Bool

    private static var cachedRules: WKContentRuleList?

    private static let adDomains = [
        "exoclick", "exosrv", "juicyads", "jads.co", "trafficjunky", "tjtraff",
        "trafficstars", "tsyndicate", "popads", "popcash", "popunder", "adsterra",
        "adstrck", "hilltopads", "clickadu", "admaven", "ad-maven", "ero-advertising",
        "plugrush", "propeller", "propclick", "doubleclick", "googlesyndication",
        "adservice.google", "adnxs", "taboola", "outbrain", "mgid", "revcontent",
        "realsrv", "adspyglass", "trafficfactory", "traffichaus", "adcash",
        "betweendigital", "coinzilla", "push.house"
    ]

    static func isAdURL(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return adDomains.contains { lower.contains($0) }
    }

    private static func loadContentRules(_ done: @escaping (WKContentRuleList?) -> Void) {
        if let cachedRules {
            done(cachedRules)
            return
        }
        guard let url = Bundle.main.url(forResource: "blockerList", withExtension: "json"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            done(nil)
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "adblock-v1",
            encodedContentRuleList: source
        ) { list, _ in
            cachedRules = list
            DispatchQueue.main.async { done(list) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true

        let store = WKWebsiteDataStore.default()
        if let proxyConfiguration = controller.activeConfig {
            store.proxyConfigurations = [proxyConfiguration]
        }
        configuration.websiteDataStore = store

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        model.webView = webView

        if adsBlocked {
            WebView.loadContentRules { list in
                if let list {
                    webView.configuration.userContentController.add(list)
                }
                webView.load(URLRequest(url: self.homeURL))
            }
        } else {
            webView.load(URLRequest(url: homeURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: BrowserModel
        private let controller: ProxyController

        init(model: BrowserModel, controller: ProxyController) {
            self.model = model
            self.controller = controller
        }

        private func isActive(_ webView: WKWebView) -> Bool {
            webView === model.webView
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard isActive(webView) else { return }
            model.syncState()
            controller.navigationFinished()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard isActive(webView) else { return }
            model.syncState()
            controller.navigationFailed()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard isActive(webView) else { return }
            model.syncState()
            controller.navigationFailed()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame?.isMainFrame == true,
               let url = navigationAction.request.url,
               WebView.isAdURL(url) {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard isActive(webView) else { return nil }
            if let url = navigationAction.request.url, WebView.isAdURL(url) {
                return nil
            }
            if navigationAction.targetFrame?.isMainFrame != true {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
