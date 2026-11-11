import SwiftUI
import WebKit

@MainActor
final class BrowserModel: ObservableObject {
    weak var webView: WKWebView?

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false

    private var feedsJSON: String?

    func syncState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
        isLoading = webView?.isLoading ?? false
    }

    /// يُستدعى عند انتهاء تحميل أي صفحة — يحقن بيانات الصفحة الرئيسية لو كانت معروضة
    func pageFinished() {
        syncState()
        injectFeedsIfNeeded()
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

    // MARK: - بيانات الصفحة الرئيسية (الرائج / الأحدث)

    func fetchFeeds() async {
        async let trending = Self.fetchSection(ordering: "mostviewed")
        async let newest = Self.fetchSection(ordering: "newest")
        let dict: [String: Any] = [
            "trending": await trending,
            "newest": await newest,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return }
        feedsJSON = json
        injectFeedsIfNeeded()
    }

    private func injectFeedsIfNeeded() {
        guard let feedsJSON, webView?.url?.isFileURL == true else { return }
        webView?.evaluateJavaScript("window.setData(\(feedsJSON))", completionHandler: nil)
    }

    /// يجرب المصادر بالترتيب ويرجع أول قائمة غير فاضية
    nonisolated static func fetchSection(ordering: String) async -> [[String: Any]] {
        let fetchers: [(String) async throws -> [[String: Any]]] = [fetchPH, fetchRT, fetchEP]
        for fetcher in fetchers {
            if let items = try? await fetcher(ordering), !items.isEmpty {
                return items
            }
        }
        return []
    }

    // MARK: - المصادر

    nonisolated static func apiGET(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    nonisolated static func jsonDict(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    nonisolated static func norm(title: Any?, url: Any?, thumb: Any?,
                                 duration: Any?, views: Any?, site: String) -> [String: Any]? {
        guard let t = title as? String, !t.isEmpty,
              let u = url as? String, u.hasPrefix("http"),
              let th = thumb as? String, th.hasPrefix("http") else { return nil }
        return [
            "title": t,
            "url": u,
            "thumb": th,
            "duration": duration ?? "",
            "views": views ?? 0,
            "site": site,
        ]
    }

    nonisolated static func fetchPH(_ ordering: String) async throws -> [[String: Any]] {
        var c = URLComponents(string: "https://www.pornhub.com/webmasters/search")!
        c.queryItems = [
            URLQueryItem(name: "search", value: ""),
            URLQueryItem(name: "ordering", value: ordering),
            URLQueryItem(name: "period", value: "weekly"),
            URLQueryItem(name: "thumbsize", value: "large_hd"),
            URLQueryItem(name: "count", value: "30"),
        ]
        let obj = jsonDict(try await apiGET(c.url!))
        let vids = obj?["videos"] as? [[String: Any]] ?? []
        return vids.compactMap {
            norm(title: $0["title"], url: $0["url"],
                 thumb: $0["thumb"] ?? $0["default_thumb"],
                 duration: $0["duration"], views: $0["views"], site: "Pornhub")
        }
    }

    nonisolated static func fetchRT(_ ordering: String) async throws -> [[String: Any]] {
        var c = URLComponents(string: "https://api.redtube.com/")!
        c.queryItems = [
            URLQueryItem(name: "data", value: "redtube.Videos.searchVideos"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "ordering", value: ordering),
            URLQueryItem(name: "period", value: "weekly"),
            URLQueryItem(name: "thumbsize", value: "big"),
            URLQueryItem(name: "count", value: "30"),
        ]
        let obj = jsonDict(try await apiGET(c.url!))
        let vids = obj?["videos"] as? [[String: Any]] ?? []
        return vids.compactMap { wrapper in
            let v = (wrapper["video"] as? [String: Any]) ?? wrapper
            return norm(title: v["title"], url: v["url"],
                        thumb: v["thumb"] ?? v["default_thumb"],
                        duration: v["duration"], views: v["views"], site: "RedTube")
        }
    }

    nonisolated static func fetchEP(_ ordering: String) async throws -> [[String: Any]] {
        var c = URLComponents(string: "https://www.eporner.com/api/v2/video/search/")!
        c.queryItems = [
            URLQueryItem(name: "query", value: "all"),
            URLQueryItem(name: "per_page", value: "30"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "thumbsize", value: "big"),
            URLQueryItem(name: "order", value: ordering == "newest" ? "latest" : "top-weekly"),
        ]
        let obj = jsonDict(try await apiGET(c.url!))
        let vids = obj?["videos"] as? [[String: Any]] ?? []
        return vids.compactMap { v in
            let thumbs = v["thumbs"] as? [[String: Any]]
            let thumb = thumbs?.first?["src"] as? String
                ?? (v["default_thumb"] as? [String: Any])?["src"] as? String
            return norm(title: v["title"], url: v["url"], thumb: thumb,
                        duration: v["length_min"], views: v["views"], site: "Eporner")
        }
    }
}
