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
}
