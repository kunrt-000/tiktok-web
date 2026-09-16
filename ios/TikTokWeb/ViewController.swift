import UIKit
import WebKit

/// 把一个网页装进 iOS App 的外壳（与安卓版功能对齐）。
/// 主页加载 tiktok，个人主页(Profile)右上角显示 Shop / Merchant 两个入口，
/// 进入商城/商家页后左上角显示返回键。
final class ViewController: UIViewController {

    // MARK: - 加密地址（与安卓版一致，运行时还原，不落明文）
    private static let HOME_ENC: [Int32] = [
        65, 108, 134, 246, 27, 92, 229, 90, 128, 197, 111, 130, 167,
        149, 17, 123, 237, 107, 15, 84, 176, 98, 171
    ]
    private static let HOME_SEED: Int32 = 0x6D2B79F5

    private static let MALL_ENC: [Int32] = [
        254, 229, 207, 21, 21, 17, 48, 50, 139, 196, 72, 134, 163,
        64, 125, 74, 41, 206, 191, 124, 89, 8
    ]
    private static let MALL_SEED: Int32 = 0x1B873593

    private static let MERCHANT_ENC: [Int32] = [
        163, 156, 130, 188, 4, 84, 169, 46, 150, 75, 91, 156, 231,
        244, 223, 191, 163, 83, 67, 99, 35, 183
    ]
    private static let MERCHANT_SEED: Int32 = Int32(bitPattern: 0x9E3779B9)

    /// 还原地址：线性同余推进密钥流，逐字符异或解密（与安卓 restore 算法一致）
    private static func restore(_ data: [Int32], _ seed: Int32) -> String {
        var k = seed
        var result = ""
        for d in data {
            k = k &* 1103515245 &+ 12345          // 32 位溢出，模拟 Java int
            let b = UInt32(bitPattern: k) >> 16   // 无符号右移 16 位
            let value = Int(d ^ Int32(b & 0xFF))
            result.append(Character(UnicodeScalar(value)!))
        }
        return result
    }

    private var webView: WKWebView!

    private let homeUrl = ViewController.restore(ViewController.HOME_ENC, ViewController.HOME_SEED)
    private let mallUrl = ViewController.restore(ViewController.MALL_ENC, ViewController.MALL_SEED)
    private let merchantUrl = ViewController.restore(ViewController.MERCHANT_ENC, ViewController.MERCHANT_SEED)

    private var shopButton: UIBarButtonItem!
    private var merchantButton: UIBarButtonItem!
    private var backButton: UIBarButtonItem!

    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupNavigationBar()
        if let url = URL(string: homeUrl) {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - WebView
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        // 伪装成 Chrome 手机浏览器，降低被站点降级处理的概率
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
        view.addSubview(webView)
    }

    // MARK: - 导航栏
    private func setupNavigationBar() {
        shopButton = UIBarButtonItem(title: "Shop", style: .plain, target: self, action: #selector(tapShop))
        merchantButton = UIBarButtonItem(title: "Merchant", style: .plain, target: self, action: #selector(tapMerchant))
        backButton = UIBarButtonItem(title: "‹ Back", style: .plain, target: self, action: #selector(tapBack))
        navigationItem.title = "TikTok"
    }

    @objc private func tapShop() {
        if let url = URL(string: mallUrl) {
            webView.load(URLRequest(url: url))
        }
    }

    @objc private func tapMerchant() {
        if let url = URL(string: merchantUrl) {
            webView.load(URLRequest(url: url))
        }
    }

    @objc private func tapBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    // MARK: - 页面状态刷新
    private func refreshUI(_ url: URL?) {
        let urlString = url?.absoluteString ?? ""

        // 标题：商城页 Shop、商家页 Merchant，其余 TikTok
        if isTargetPage(urlString, merchantUrl) {
            navigationItem.title = "Merchant"
        } else if isTargetPage(urlString, mallUrl) {
            navigationItem.title = "Shop"
        } else {
            navigationItem.title = "TikTok"
        }

        // 入口按钮：只在个人主页(Profile)显示
        if isProfilePage(urlString) {
            navigationItem.rightBarButtonItems = [shopButton, merchantButton]
        } else {
            navigationItem.rightBarButtonItems = []
        }

        // 返回键：商城页/商家页显示
        if isTargetPage(urlString, mallUrl) || isTargetPage(urlString, merchantUrl) {
            navigationItem.leftBarButtonItem = backButton
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    // MARK: - URL 判断
    /// 判断是否停留在个人主页：/profile 或 /@用户名
    private func isProfilePage(_ url: String) -> Bool {
        let base = trimmedBase(homeUrl)
        guard url.hasPrefix(base) else { return false }
        let rest = String(url.dropFirst(base.count))
        if rest == "/profile" || rest.hasPrefix("/profile?") || rest.hasPrefix("/profile#") {
            return true
        }
        guard rest.hasPrefix("/@") else { return false }
        let afterUser = String(rest.dropFirst(2))
        guard !afterUser.isEmpty else { return false }
        return !afterUser.contains("/")
    }

    /// 判断 URL 是否属于指定入口地址本身（允许末尾 / 或 ?/# 参数）
    private func isTargetPage(_ url: String, _ target: String) -> Bool {
        let base = trimmedBase(target)
        guard url.hasPrefix(base) else { return false }
        let rest = String(url.dropFirst(base.count))
        return rest.isEmpty || rest == "/" || rest.hasPrefix("/?") || rest.hasPrefix("/#")
    }

    private func trimmedBase(_ s: String) -> String {
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }
}

// MARK: - WKNavigationDelegate
extension ViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshUI(webView.url)
    }

    /// http(s) 留在 WebView 内；其它协议（tel:、tg:、intent: 等）交给系统处理
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let urlString = navigationAction.request.url?.absoluteString else {
            decisionHandler(.cancel)
            return
        }
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            decisionHandler(.allow)
            return
        }
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        decisionHandler(.cancel)
    }
}
