import SwiftUI
import WebKit

@MainActor
final class BrowserModel: ObservableObject {
    @MainActor
    final class Tab: ObservableObject, Identifiable {
        let id = UUID()
        let webView: WKWebView
        @Published var title = ""
        @Published var url: URL?

        init(webView: WKWebView) {
            self.webView = webView
        }
    }

    @Published var tabs: [Tab] = []
    @Published var activeID: Tab.ID?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var showTabSwitcher = false
    @Published var isSearching = false

    /// ربط مخزن المفضلة لحقنها في الصفحة الرئيسية
    var favorites: FavoritesStore?

    lazy var delegate = BrowserDelegate(model: self)

    private var feedsJSON: String?
    private var resultsJSON: String?

    var activeTab: Tab? { tabs.first { $0.id == activeID } }
    var webView: WKWebView? { activeTab?.webView }

    func syncState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
        isLoading = webView?.isLoading ?? false
    }

    // MARK: - التبويبات

    func ensureTab(config: BrowserConfig, home: String) {
        if tabs.isEmpty {
            newTab(config: config, home: home)
        }
    }

    func newTab(config: BrowserConfig, home: String) {
        WebViewFactory.make(config: config, delegate: delegate) { [weak self] wv in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let tab = Tab(webView: wv)
                self.tabs.append(tab)
                self.activeID = tab.id
                self.loadHome(home)
            }
        }
    }

    func activate(_ tab: Tab) {
        activeID = tab.id
        syncState()
    }

    func close(_ tab: Tab, config: BrowserConfig, home: String) {
        tabs.removeAll { $0.id == tab.id }
        if activeID == tab.id {
            activeID = tabs.last?.id
        }
        if tabs.isEmpty {
            newTab(config: config, home: home)
        }
        syncState()
    }

    /// يعيد بناء التبويب النشط فقط (عند تغيير إعدادات تؤثر على الـ WebView)
    func rebuildActive(config: BrowserConfig, home: String) {
        guard let active = activeTab else {
            newTab(config: config, home: home)
            return
        }
        WebViewFactory.make(config: config, delegate: delegate) { [weak self] wv in
            Task { @MainActor [weak self] in
                guard let self,
                      let i = self.tabs.firstIndex(where: { $0.id == active.id }) else { return }
                let tab = Tab(webView: wv)
                self.tabs[i] = tab
                self.activeID = tab.id
                self.loadHome(home)
            }
        }
    }

    /// زر الذعر: يغلق كل التبويبات ويمسح البيانات ويفتح تبويباً نظيفاً
    func panic(config: BrowserConfig, home: String) {
        tabs.removeAll()
        activeID = nil
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
        newTab(config: config, home: home)
    }

    // MARK: - التنقل

    func pageFinished(for wv: WKWebView) {
        if let tab = tabs.first(where: { $0.webView === wv }) {
            tab.title = wv.title ?? ""
            tab.url = wv.url
        }
        if wv === webView {
            syncState()
            injectFeedsIfNeeded()
        }
    }

    /// يحمّل الصفحة الرئيسية: رابط http أو صفحة المواقع المدمجة (أي قيمة غير http)
    func loadHome(_ home: String) {
        if home.lowercased().hasPrefix("http"), let url = URL(string: home) {
            webView?.load(URLRequest(url: url))
        } else if let file = Bundle.main.url(forResource: "start", withExtension: "html") {
            webView?.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        }
    }

    /// يفتح إدخال شريط العنوان: رابط → تنقّل، وإلا بحث موحد عبر المواقع
    func open(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil,
           let url = URL(string: trimmed) {
            webView?.load(URLRequest(url: url))
        } else if !trimmed.contains(" ") && trimmed.contains("."),
                  let url = URL(string: "https://" + trimmed) {
            webView?.load(URLRequest(url: url))
        } else {
            Task { await self.search(trimmed) }
        }
    }

    // MARK: - البحث الموحد

    func search(_ query: String) async {
        isSearching = true
        let items = await Self.searchAll(query)
        isSearching = false

        guard !items.isEmpty else {
            // لو ما جا شيء نرجع لبحث عادي
            let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let url = URL(string: "https://duckduckgo.com/?q=" + q) {
                webView?.load(URLRequest(url: url))
            }
            return
        }

        let dict: [String: Any] = ["q": query, "items": items]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return }
        resultsJSON = json

        if let file = Bundle.main.url(forResource: "results", withExtension: "html") {
            webView?.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        }
    }

    nonisolated static func searchAll(_ query: String) async -> [[String: Any]] {
        async let ph = searchPH(query)
        async let rt = searchRT(query)
        async let ep = searchEP(query)
        let lists = [await ph, await rt, await ep]
        // دمج بالتناوب عشان تتنوع النتائج بين المواقع
        var merged: [[String: Any]] = []
        var i = 0
        while merged.count < 48 {
            var added = false
            for list in lists where i < list.count {
                merged.append(list[i])
                added = true
            }
            if !added { break }
            i += 1
        }
        return merged
    }

    // MARK: - بيانات الصفحة الرئيسية

    func fetchFeeds() async {
        async let trending = Self.fetchSection(ordering: "mostviewed")
        async let toprated = Self.fetchSection(ordering: "rating")
        async let longest = Self.fetchSection(ordering: "longest")
        async let newest = Self.fetchSection(ordering: "newest")
        async let onlyfans = Self.searchAll("onlyfans")
        async let cams = Self.fetchCams()
        async let stars = Self.fetchStars()
        let dict: [String: Any] = [
            "trending": await trending,
            "toprated": await toprated,
            "longest": await longest,
            "newest": await newest,
            "onlyfans": await onlyfans,
            "cams": await cams,
            "stars": await stars,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return }
        feedsJSON = json
        injectFeedsIfNeeded()
    }

    private func injectFeedsIfNeeded() {
        guard let wv = webView, let name = wv.url?.lastPathComponent else { return }
        if name == "start.html" {
            var js = "window.setData(\(feedsJSON ?? "{}"));"
            if let favorites {
                js += "window.setLists({favs:\(favorites.json("fav")),later:\(favorites.json("later"))});"
            }
            wv.evaluateJavaScript(js, completionHandler: nil)
        } else if name == "results.html", let resultsJSON {
            wv.evaluateJavaScript("window.setData(\(resultsJSON))", completionHandler: nil)
        }
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
            URLQueryItem(name: "order", value: Self.epOrder(ordering)),
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

    nonisolated static func epOrder(_ ordering: String) -> String {
        switch ordering {
        case "newest": return "latest"
        case "rating": return "top-rated"
        case "longest": return "longest"
        default: return "top-weekly"
        }
    }

    // MARK: - بحث موحد لكل مصدر

    nonisolated static func searchPH(_ query: String) async -> [[String: Any]] {
        var c = URLComponents(string: "https://www.pornhub.com/webmasters/search")!
        c.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "ordering", value: "mostviewed"),
            URLQueryItem(name: "period", value: "weekly"),
            URLQueryItem(name: "thumbsize", value: "large_hd"),
            URLQueryItem(name: "count", value: "20"),
        ]
        guard let data = try? await apiGET(c.url!), let obj = jsonDict(data) else { return [] }
        return (obj["videos"] as? [[String: Any]] ?? []).compactMap {
            norm(title: $0["title"], url: $0["url"],
                 thumb: $0["thumb"] ?? $0["default_thumb"],
                 duration: $0["duration"], views: $0["views"], site: "Pornhub")
        }
    }

    nonisolated static func searchRT(_ query: String) async -> [[String: Any]] {
        var c = URLComponents(string: "https://api.redtube.com/")!
        c.queryItems = [
            URLQueryItem(name: "data", value: "redtube.Videos.searchVideos"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "ordering", value: "mostviewed"),
            URLQueryItem(name: "period", value: "weekly"),
            URLQueryItem(name: "thumbsize", value: "big"),
            URLQueryItem(name: "count", value: "20"),
        ]
        guard let data = try? await apiGET(c.url!), let obj = jsonDict(data) else { return [] }
        return (obj["videos"] as? [[String: Any]] ?? []).compactMap { wrapper in
            let v = (wrapper["video"] as? [String: Any]) ?? wrapper
            return norm(title: v["title"], url: v["url"],
                        thumb: v["thumb"] ?? v["default_thumb"],
                        duration: v["duration"], views: v["views"], site: "RedTube")
        }
    }

    nonisolated static func searchEP(_ query: String) async -> [[String: Any]] {
        var c = URLComponents(string: "https://www.eporner.com/api/v2/video/search/")!
        c.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "thumbsize", value: "big"),
            URLQueryItem(name: "order", value: "top-weekly"),
        ]
        guard let data = try? await apiGET(c.url!), let obj = jsonDict(data) else { return [] }
        return (obj["videos"] as? [[String: Any]] ?? []).compactMap { v in
            let thumbs = v["thumbs"] as? [[String: Any]]
            let thumb = thumbs?.first?["src"] as? String
                ?? (v["default_thumb"] as? [String: Any])?["src"] as? String
            return norm(title: v["title"], url: v["url"], thumb: thumb,
                        duration: v["length_min"], views: v["views"], site: "Eporner")
        }
    }

    // MARK: - الكاميرات المباشرة

    /// غرف البث المباشر من الـ API العام لـ Chaturbate
    nonisolated static func fetchCams() async -> [[String: Any]] {
        var c = URLComponents(string: "https://chaturbate.com/api/public/affiliates/onlinerooms/")!
        c.queryItems = [
            URLQueryItem(name: "wm", value: "9cgHy"),
            URLQueryItem(name: "client_ip", value: "0.0.0.0"),
            URLQueryItem(name: "limit", value: "60"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let data = try? await apiGET(c.url!), let obj = jsonDict(data) else { return [] }
        let rooms = obj["results"] as? [[String: Any]] ?? []
        return rooms.compactMap { r in
            guard let user = r["username"] as? String, !user.isEmpty,
                  let thumb = (r["image_url_360x270"] as? String) ?? (r["image_url"] as? String),
                  thumb.hasPrefix("http") else { return nil }
            let embed = r["iframe_embed"] as? String ?? ""
            let url = Self.extractSrc(embed)
                ?? (r["chat_room_url"] as? String)
                ?? "https://chaturbate.com/\(user)/"
            return [
                "username": user,
                "name": ((r["display_name"] as? String) ?? "").isEmpty ? user : (r["display_name"] as! String),
                "thumb": thumb,
                "viewers": r["num_users"] ?? 0,
                "url": url,
                "g": r["gender"] as? String ?? "",
            ]
        }
    }

    /// يستخرج رابط src من كود iframe
    nonisolated static func extractSrc(_ s: String) -> String? {
        guard let a = s.range(of: "src='"),
              let b = s[a.upperBound...].range(of: "'") else { return nil }
        return String(s[a.upperBound..<b.lowerBound])
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - النجوم

    /// يجرب endpoint الغني (صور) ثم قائمة الأسماء كاحتياط
    nonisolated static func fetchStars() async -> [[String: Any]] {
        if let rich = try? await fetchStarsRich(), !rich.isEmpty {
            return rich
        }
        if let names = try? await fetchStarNames(), !names.isEmpty {
            return names
        }
        return []
    }

    nonisolated static func fetchStarsRich() async throws -> [[String: Any]] {
        var c = URLComponents(string: "https://www.pornhub.com/webmasters/stars")!
        c.queryItems = [URLQueryItem(name: "count", value: "30")]
        let obj = jsonDict(try await apiGET(c.url!))
        let stars = obj?["pornstars"] as? [[String: Any]] ?? []
        return stars.compactMap { s in
            let name = s["star_name"] as? String ?? s["name"] as? String
            let url = s["star_url"] as? String ?? s["url"] as? String
            let thumb = s["star_thumb"] as? String ?? s["thumb"] as? String ?? s["photo_url"] as? String
            guard let n = name, !n.isEmpty else { return nil }
            var out: [String: Any] = [
                "name": n,
                "url": url ?? Self.starURL(n),
            ]
            if let thumb, thumb.hasPrefix("http") {
                out["thumb"] = thumb
            }
            return out
        }
    }

    nonisolated static func fetchStarNames() async throws -> [[String: Any]] {
        var c = URLComponents(string: "https://www.pornhub.com/webmasters/pornstars")!
        c.queryItems = [URLQueryItem(name: "count", value: "30")]
        let obj = jsonDict(try await apiGET(c.url!))
        let names = obj?["pornstars"] as? [String] ?? []
        return names.prefix(30).map {
            ["name": $0, "url": Self.starURL($0)]
        }
    }

    nonisolated static func starURL(_ name: String) -> String {
        let slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        return "https://www.pornhub.com/pornstar/" + slug
    }
}
