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

    /// يفتح إدخال شريط العنوان: رابط كامل، أو دومين، أو بحث DuckDuckGo
    func open(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var url: URL?
        if trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil {
            url = URL(string: trimmed)
        } else if !trimmed.contains(" ") && trimmed.contains(".") {
            url = URL(string: "https://" + trimmed)
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            url = URL(string: "https://duckduckgo.com/?q=" + query)
        }
        if let url {
            webView?.load(URLRequest(url: url))
        }
    }
}
