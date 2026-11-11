import Foundation

@MainActor
final class FavoritesStore: ObservableObject {
    struct Item: Codable, Identifiable, Equatable {
        let url: String
        let title: String
        let site: String
        let kind: String   // "fav" | "later"
        let created: Date

        var id: String { kind + "|" + url }
    }

    @Published private(set) var items: [Item] = []
    private let key = "browser.favorites.v1"

    init() {
        load()
    }

    func isSaved(_ url: String?, kind: String) -> Bool {
        guard let url, !url.isEmpty else { return false }
        return items.contains { $0.url == url && $0.kind == kind }
    }

    /// يضيف أو يزيل العنصر (toggle) — المضاف حديثاً يطلع أول القائمة
    func toggle(title: String?, url: URL, kind: String) {
        let u = url.absoluteString
        if let i = items.firstIndex(where: { $0.url == u && $0.kind == kind }) {
            items.remove(at: i)
        } else {
            let item = Item(
                url: u,
                title: (title?.isEmpty == false) ? title! : (url.host ?? u),
                site: url.host ?? "",
                kind: kind,
                created: Date()
            )
            items.insert(item, at: 0)
        }
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// JSON للحقن في الصفحة الرئيسية لنوع معين
    func json(_ kind: String) -> String {
        let arr: [[String: String]] = items
            .filter { $0.kind == kind }
            .prefix(30)
            .map { ["title": $0.title, "url": $0.url, "site": $0.site] }
        guard let d = try? JSONSerialization.data(withJSONObject: arr) else { return "[]" }
        return String(data: d, encoding: .utf8) ?? "[]"
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([Item].self, from: d) else { return }
        items = arr
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
}
