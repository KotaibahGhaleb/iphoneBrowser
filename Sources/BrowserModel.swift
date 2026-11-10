import SwiftUI
import WebKit

@MainActor
final class BrowserModel: ObservableObject {
    weak var webView: WKWebView?

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false

    func syncState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
        isLoading = webView?.isLoading ?? false
    }

    /// يحمّل الصفحة الرئيسية: رابط http أو صفحة المواقع المدمجة (أي قيمة غير http)
    func loadHome(_ home: String) {
        if home.lowercased().hasPrefix("http"), let url = URL(string: home) {
            webView?.load(URLRequest(url: url))
        } else if let file = Bundle.main.url(forResource: "start", withExtension: "html") {
            webView?.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        }
    }
}
