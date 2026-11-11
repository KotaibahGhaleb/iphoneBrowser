import SwiftUI
import WebKit

struct BrowserConfig {
    var adsBlocked = true
    var hoverPreview = true
    var incognito = true
}

enum WebViewFactory {
    private static var cachedRules: WKContentRuleList?

    static let adDomains = [
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

    @MainActor
    static func make(config: BrowserConfig,
                     delegate: WKNavigationDelegate & WKUIDelegate,
                     done: @escaping (WKWebView) -> Void) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.websiteDataStore = config.incognito ? .nonPersistent() : .default()

        if config.hoverPreview {
            configuration.userContentController.addUserScript(WKUserScript(
                source: hoverPreviewJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = !config.hoverPreview

        if config.adsBlocked {
            loadContentRules { rules in
                DispatchQueue.main.async {
                    if let rules {
                        webView.configuration.userContentController.add(rules)
                    }
                    done(webView)
                }
            }
        } else {
            done(webView)
        }
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

    // يحوّل اللمسة المطوّلة إلى أحداث ماوس (mouseover/mousemove/mouseout)
    // حتى تشتغل معاينات الفيديو اللي تعتمد على hover
    static let hoverPreviewJS = """
    (function() {
        var timer = null, sx = 0, sy = 0, hovering = false;

        function fire(type, x, y) {
            var el = document.elementFromPoint(x, y);
            if (!el) return;
            el.dispatchEvent(new MouseEvent(type, {
                bubbles: true, cancelable: true, view: window,
                clientX: x, clientY: y, screenX: x, screenY: y
            }));
        }

        function startHover() { hovering = true; fire('mouseover', sx, sy); fire('mousemove', sx, sy); }
        function stopHover() {
            if (!hovering) return;
            hovering = false;
            fire('mousemove', sx, sy);
            fire('mouseout', sx, sy);
        }

        document.addEventListener('touchstart', function(e) {
            if (e.touches.length !== 1) return;
            var t = e.touches[0];
            sx = t.clientX; sy = t.clientY;
            timer = setTimeout(startHover, 350);
        }, { passive: true });

        document.addEventListener('touchmove', function(e) {
            var t = e.touches[0];
            if (!t) return;
            var dx = t.clientX - sx, dy = t.clientY - sy;
            if (!hovering && (dx * dx + dy * dy > 100)) {
                if (timer) { clearTimeout(timer); timer = null; }
                return;
            }
            sx = t.clientX; sy = t.clientY;
            if (hovering) fire('mousemove', sx, sy);
        }, { passive: true });

        document.addEventListener('touchend', function() {
            if (timer) { clearTimeout(timer); timer = null; }
            stopHover();
        }, { passive: true });

        document.addEventListener('touchcancel', function() {
            if (timer) { clearTimeout(timer); timer = null; }
            stopHover();
        }, { passive: true });

        var style = document.createElement('style');
        style.textContent = '* { -webkit-touch-callout: none !important; }';
        (document.head || document.documentElement).appendChild(style);
    })();
    """
}

/// غلاف عرض بسيط يعرض WKWebView جاهزة (للتبويب النشط)
struct WebHostView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
final class BrowserDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: BrowserModel?

    init(model: BrowserModel) {
        self.model = model
    }

    private func isActive(_ webView: WKWebView) -> Bool {
        webView === model?.webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        model?.pageFinished(for: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isActive(webView) else { return }
        model?.syncState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard isActive(webView) else { return }
        model?.syncState()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url,
           WebViewFactory.isAdURL(url) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard isActive(webView) else { return nil }
        if let url = navigationAction.request.url, WebViewFactory.isAdURL(url) {
            return nil
        }
        if navigationAction.targetFrame?.isMainFrame != true {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
