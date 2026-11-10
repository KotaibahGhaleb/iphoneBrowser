import Foundation
import Network
import NetworkExtension
import SwiftUI

enum ProxyMode: String, CaseIterable, Identifiable {
    case auto
    case manual
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "تلقائي — بروكسيات مجانية"
        case .manual: return "يدوي — بروكسي خاص"
        case .off: return "بدون بروكسي"
        }
    }
}

enum ManualProxyType: String, CaseIterable, Identifiable {
    case socks5 = "SOCKS5"
    case httpConnect = "HTTP CONNECT"

    var id: String { rawValue }
}

@MainActor
final class ProxyController: ObservableObject {
    struct Candidate {
        let label: String
        let config: ProxyConfiguration
    }

    private static let maxAttempts = 25

    @Published private(set) var activeConfig: ProxyConfiguration?
    @Published private(set) var revision = 0
    @Published private(set) var status = ""

    private var candidates: [Candidate] = []
    private var index = 0
    private var settled = false
    private var fetching = false
    private var mode: ProxyMode = .off
    private var generation = 0
    private var lastManual: ProxyConfiguration?
    private var timeoutTask: Task<Void, Never>?

    func configure(mode: ProxyMode, manual manualConfig: ProxyConfiguration?) {
        self.mode = mode
        lastManual = manualConfig
        generation += 1
        timeoutTask?.cancel()
        settled = false
        fetching = false
        candidates = []
        index = 0

        switch mode {
        case .off:
            status = ""
            activate(nil)
        case .manual:
            status = manualConfig == nil ? "أدخل بيانات البروكسي من الإعدادات" : ""
            activate(manualConfig)
        case .auto:
            status = "جاري جلب قائمة بروكسيات مجانية…"
            fetching = true
            activate(nil)
            Task { await self.fetchAndStart() }
        }
    }

    func retry() {
        configure(mode: mode, manual: lastManual)
    }

    func navigationFinished() {
        switch mode {
        case .auto:
            guard !settled else { return }
            settled = true
            fetching = false
            timeoutTask?.cancel()
            status = "تم الاتصال"
        case .manual:
            if !settled {
                settled = true
                status = ""
            }
        case .off:
            break
        }
    }

    func navigationFailed() {
        guard !settled else { return }
        switch mode {
        case .auto:
            guard !fetching else { return }
            timeoutTask?.cancel()
            tryNext()
        case .manual:
            settled = true
            status = "البروكسي اليدوي ما اشتغل — تأكد من البيانات أو جرّب نوعاً آخر"
        case .off:
            break
        }
    }

    private func activate(_ config: ProxyConfiguration?) {
        activeConfig = config
        revision += 1
    }

    private func tryNext() {
        let limit = min(candidates.count, Self.maxAttempts)
        guard index < limit else {
            settled = true
            activate(nil)
            status = "ما لقينا بروكسي شغال — جرّب «إعادة البحث» أو رابط مرآة"
            return
        }
        let candidate = candidates[index]
        index += 1
        status = "تجربة بروكسي \(index)/\(limit): \(candidate.label)"
        activate(candidate.config)
        armTimeout()
    }

    private func armTimeout() {
        timeoutTask?.cancel()
        let gen = generation
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, !Task.isCancelled, self.generation == gen, !self.settled else { return }
            self.tryNext()
        }
    }

    private func fetchAndStart() async {
        let gen = generation
        let list = await Self.fetchProxyCandidates()
        fetching = false
        guard generation == gen, mode == .auto, !settled else { return }
        guard !list.isEmpty else {
            settled = true
            status = "تعذّر جلب قائمة البروكسيات — تأكد من الاتصال بالإنترنت"
            return
        }
        candidates = list.shuffled()
        index = 0
        tryNext()
    }

    static func fetchProxyCandidates() async -> [Candidate] {
        let sources: [(url: String, defaultScheme: String)] = [
            ("https://api.proxyscrape.com/v3/free-proxy-list/get?request=displayproxies&proxy_format=protocolipport&format=text&timeout=5000", "socks5"),
            ("https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt", "socks5"),
        ]
        var all: [Candidate] = []
        var seen = Set<String>()
        for source in sources {
            guard let url = URL(string: source.url) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let text = String(data: data, encoding: .utf8) else { continue }
                for candidate in parse(text, defaultScheme: source.defaultScheme)
                where seen.insert(candidate.label).inserted {
                    all.append(candidate)
                }
            } catch {
                continue
            }
        }
        return all
    }

    static func parse(_ text: String, defaultScheme: String) -> [Candidate] {
        var out: [Candidate] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if !line.contains("://") {
                line = "\(defaultScheme)://\(line)"
            }
            guard let url = URL(string: line),
                  let host = url.host, !host.isEmpty,
                  let port = url.port,
                  let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { continue }
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
            let config: ProxyConfiguration
            switch url.scheme?.lowercased() {
            case "socks5":
                config = ProxyConfiguration(socksv5Proxy: endpoint)
            case "http":
                config = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
            default:
                continue
            }
            config.allowFailover = false
            out.append(Candidate(label: "\(host):\(port)", config: config))
        }
        return out
    }

    static func manual(type: ManualProxyType, host: String, port: Int,
                       username: String, password: String) -> ProxyConfiguration? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(trimmed), port: nwPort)
        let config: ProxyConfiguration
        switch type {
        case .socks5:
            config = ProxyConfiguration(socksv5Proxy: endpoint)
        case .httpConnect:
            config = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
        }
        config.allowFailover = false
        if !username.isEmpty {
            config.applyCredential(username: username, password: password)
        }
        return config
    }
}
