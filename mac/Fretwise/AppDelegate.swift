import Cocoa
import WebKit

/// Fretwise for the Mac: the same page as the iPhone app (the repo's web/ folder, bundled as "web"),
/// in a resizable window with a menu bar. The page is served from the app bundle on the fretwise://
/// scheme rather than as a file, because it fetches its guitar samples and needs a secure origin for
/// the microphone; a file:// page gets neither.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let shared = AppDelegate()   // NSApplication only keeps a weak reference to its delegate

    static func main() {
        let app = NSApplication.shared
        app.delegate = shared
        app.setActivationPolicy(.regular)
        app.run()
    }

    private var window: NSWindow!
    private var web: WKWebView!
    private let messages = PageMessages()
    private let files = BundleFiles()

    // Progress sync with the iPhone app through iCloud key-value storage. Same protocol as the iPhone
    // app's AppDelegate: the page sends {"op":"hello"} or {"op":"put","key","value"} on "fwSync" and
    // gets iCloud's values through window.__fwSyncIn, which merges them into its own.
    private let cloud = NSUbiquitousKeyValueStore.default
    private let syncKeys = ["learn", "days", "stats", "prefs"]
    private static let site = "https://aeharper98.github.io/fretwise/"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        messages.delegate = self

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(files, forURLScheme: BundleFiles.scheme)
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(messages, name: "fwSync")
        config.userContentController.addUserScript(WKUserScript(source: "window.__FW_MAC = true;",
                                                                injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let frame = NSRect(x: 0, y: 0, width: 1180, height: 820)
        web = WKWebView(frame: frame, configuration: config)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.autoresizingMask = [.width, .height]

        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Fretwise"
        window.minSize = NSSize(width: 720, height: 560)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.center()
        window.setFrameAutosaveName("Fretwise")
        window.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(self, selector: #selector(cloudChanged(_:)),
                                               name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud)
        cloud.synchronize()

        web.load(URLRequest(url: URL(string: "\(BundleFiles.scheme)://app/index.html")!))
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        cloud.synchronize()
        sendCloudToPage(nil)
    }

    // MARK: - Progress sync

    func received(_ message: WKScriptMessage) {
        guard message.name == "fwSync", let body = message.body as? String,
              let data = body.data(using: .utf8),
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let op = msg["op"] as? String else { return }
        if op == "hello" {
            cloud.synchronize()
            sendCloudToPage(nil)
        } else if op == "put", let key = msg["key"] as? String, syncKeys.contains(key), let value = msg["value"] as? String {
            if cloud.string(forKey: key) != value { cloud.set(value, forKey: key) }
        }
    }

    @objc private func cloudChanged(_ note: Notification) {
        let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        DispatchQueue.main.async { self.sendCloudToPage(keys) }
    }

    /// Hands iCloud's copy of the given keys (all of them for nil) to the page, which merges it.
    private func sendCloudToPage(_ keys: [String]?) {
        guard let web = web else { return }
        var values: [String: String] = [:]
        for key in keys ?? syncKeys where syncKeys.contains(key) {
            if let value = cloud.string(forKey: key) { values[key] = value }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let json = String(data: data, encoding: .utf8) else { return }
        web.callAsyncJavaScript("if (window.__fwSyncIn) window.__fwSyncIn(JSON.parse(s));", arguments: ["s": json],
                                in: nil, in: .page, completionHandler: nil)
    }

    // MARK: - Menu bar

    private func buildMenu() {
        let bar = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            item.submenu = m
            bar.addItem(item)
            return m
        }
        func add(_ m: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                 _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, command: String? = nil) {
            let item = m.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            item.representedObject = command
        }

        let app = menu("Fretwise")
        add(app, "About Fretwise", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        add(app, "Hide Fretwise", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit Fretwise", #selector(NSApplication.terminate(_:)), "q")

        let edit = menu("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")

        let go = menu("Go")
        for (i, tab) in ["Learn", "Practice", "Explore", "Tune"].enumerated() {
            add(go, tab, #selector(pageCommand(_:)), String(i + 1), target: self, command: tab.lowercased())
        }
        go.addItem(.separator())
        add(go, "Find the Key and Play Along", #selector(pageCommand(_:)), "k", target: self, command: "key")

        let view = menu("View")
        add(view, "Zoom In", #selector(zoomIn(_:)), "+", target: self)
        add(view, "Zoom Out", #selector(zoomOut(_:)), "-", target: self)
        add(view, "Actual Size", #selector(zoomReset(_:)), "0", target: self)
        view.addItem(.separator())
        add(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        let win = menu("Window")
        add(win, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(win, "Zoom", #selector(NSWindow.performZoom(_:)))
        win.addItem(.separator())
        add(win, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))

        NSApp.mainMenu = bar
        NSApp.windowsMenu = win
    }

    @objc private func pageCommand(_ sender: NSMenuItem) {
        guard let cmd = sender.representedObject as? String else { return }
        web.evaluateJavaScript("window.__fwMac && window.__fwMac('\(cmd)')", completionHandler: nil)
    }

    @objc private func zoomIn(_ sender: Any?) { web.pageZoom = min(2, web.pageZoom + 0.1) }
    @objc private func zoomOut(_ sender: Any?) { web.pageZoom = max(0.6, web.pageZoom - 0.1) }
    @objc private func zoomReset(_ sender: Any?) { web.pageZoom = 1 }
}

extension AppDelegate: WKUIDelegate, WKNavigationDelegate {
    /// macOS asks the person the first time (NSMicrophoneUsageDescription); the page only ever wants the microphone.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }

    /// The app window only ever shows index.html. Other pages (privacy, support) and outside links open in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow); return
        }
        if scheme == BundleFiles.scheme {
            let page = url.lastPathComponent
            if navigationAction.targetFrame?.isMainFrame != false, !page.isEmpty, page != "index.html", page.hasSuffix(".html"),
               let online = URL(string: AppDelegate.site + page) {
                NSWorkspace.shared.open(online)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow); return
        }
        if ["http", "https", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    /// If the page's process dies (it can under memory pressure), load it again rather than leave a blank window.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

/// Passes the page's messages to the app delegate. WKUserContentController keeps its handlers strongly,
/// so this holds the delegate weakly.
final class PageMessages: NSObject, WKScriptMessageHandler {
    weak var delegate: AppDelegate?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.received(message)
    }
}

/// Serves the bundled web/ folder on fretwise://app/…
final class BundleFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "fretwise"
    private let root = Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true).standardizedFileURL

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1",
                                                     headerFields: ["Content-Type": "text/plain"])!)
            urlSchemeTask.didReceive(Data("Not found".utf8))
            urlSchemeTask.didFinish()
            return
        }
        let headers = ["Content-Type": BundleFiles.type(of: file.pathExtension),
                       "Content-Length": String(data.count),
                       "Cache-Control": "no-cache"]
        urlSchemeTask.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static func type(of ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "webmanifest": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "wav": return "audio/wav"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "txt", "md": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
