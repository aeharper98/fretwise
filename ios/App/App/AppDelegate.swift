import UIKit
import AVFoundation
import MediaPlayer
import WebKit
import Capacitor

/// Passes messages from the web pages to the app delegate. It holds the delegate weakly because
/// WKUserContentController keeps a strong reference to its message handlers.
final class ScreenMessages: NSObject, WKScriptMessageHandler {
    weak var delegate: AppDelegate?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.received(message)
    }
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    // Second screen (AirPlay or a cable): instead of a copy of the phone, the TV gets its own window
    // running the page in display mode. The phone page sends a snapshot of what it shows ("fwDisplay");
    // this passes it to the TV page, which says "ready" ("fwTV") once it has loaded.
    private let messages = ScreenMessages()
    private var phoneHooked = false
    private var tvWindow: UIWindow?
    private var tvView: WKWebView?
    private var tvReady = false
    private var tvLatest: String?

    // Drive mode: audio-only practice for the car. While it runs Fretwise is the "Now Playing" app, so
    // CarPlay, the lock screen and Control Centre show the question, and the steering wheel's next,
    // previous and play/pause buttons skip, repeat and pause. The page sends its state on "fwDrive".
    private var driveOn = false
    private var driveCommandsAdded = false
    private lazy var driveArtwork: MPMediaItemArtwork? = {
        guard let url = Bundle.main.url(forResource: "public/icons/icon-512", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    // Progress sync with the Mac app: the page keeps progress in localStorage and mirrors it to iCloud
    // key-value storage on "fwSync" ({"op":"hello"} or {"op":"put","key","value"}); iCloud's values go
    // back to the page through window.__fwSyncIn, which merges them. The Mac app does the same.
    private let cloud = NSUbiquitousKeyValueStore.default
    private let syncKeys = ["learn", "days", "stats", "prefs"]

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureAudioSession()
        messages.delegate = self
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screenDidConnect(_:)), name: UIScreen.didConnectNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDidDisconnect(_:)), name: UIScreen.didDisconnectNotification, object: nil)
        center.addObserver(self, selector: #selector(cloudChanged(_:)), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud)
        cloud.synchronize()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    /// Lets Fretwise play guitar notes and listen through the microphone at the same time,
    /// keeps sound on the loudspeaker (not the earpiece) while listening, and plays even
    /// when the ring/silent switch is set to silent.
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Fretwise: audio session setup failed: \(error)")
        }
    }

    /// Drive mode plays through the car like a podcast app: playback only, not mixed with other audio,
    /// which is what makes Fretwise the Now Playing app. Listening is never on in Drive mode.
    func configureDriveSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            print("Fretwise: drive audio session setup failed: \(error)")
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if driveOn { configureDriveSession() } else { configureAudioSession() }
        hookPhonePage()
        cloud.synchronize()
        sendCloudToPage(nil)
        if tvWindow == nil, let screen = UIScreen.screens.dropFirst().first {
            showTV(on: screen)
        }
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    // MARK: - Second screen

    private var phoneWebView: WKWebView? {
        return (window?.rootViewController as? CAPBridgeViewController)?.bridge?.webView
    }

    private func hookPhonePage() {
        guard !phoneHooked, let web = phoneWebView else { return }
        web.configuration.userContentController.add(messages, name: "fwDisplay")
        web.configuration.userContentController.add(messages, name: "fwDrive")
        web.configuration.userContentController.add(messages, name: "fwSync")
        phoneHooked = true
    }

    @objc private func screenDidConnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen else { return }
        hookPhonePage()
        showTV(on: screen)
    }

    @objc private func screenDidDisconnect(_ note: Notification) {
        hideTV()
        if let screen = UIScreen.screens.dropFirst().first {
            showTV(on: screen)
        } else {
            tellPhone()
        }
    }

    private func showTV(on screen: UIScreen) {
        hideTV()
        let config = WKWebViewConfiguration()
        config.userContentController.add(messages, name: "fwTV")
        config.userContentController.addUserScript(WKUserScript(source: "window.__FW_DISPLAY = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: screen.bounds, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.067, alpha: 1)
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        let controller = UIViewController()
        controller.view = web

        let win: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.screen == screen }) {
            win = UIWindow(windowScene: scene)
            win.frame = screen.bounds
        } else {
            win = UIWindow(frame: screen.bounds)
            win.screen = screen
        }
        win.rootViewController = controller
        win.isHidden = false
        tvWindow = win
        tvView = web
        tvReady = false
        if let dir = Bundle.main.url(forResource: "public", withExtension: nil) {
            web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }
        tellPhone()
    }

    private func hideTV() {
        tvView?.configuration.userContentController.removeScriptMessageHandler(forName: "fwTV")
        tvWindow?.isHidden = true
        tvWindow = nil
        tvView = nil
        tvReady = false
    }

    /// Tells the phone page whether a TV is showing the big view, so it starts or stops sending.
    private func tellPhone() {
        let on = tvWindow != nil ? "true" : "false"
        phoneWebView?.evaluateJavaScript("window.__fwScreen && window.__fwScreen(\(on))", completionHandler: nil)
    }

    private func sendToTV(_ json: String) {
        guard tvReady, let web = tvView else { return }
        web.callAsyncJavaScript("if (window.__fwDisplay) window.__fwDisplay(s);", arguments: ["s": json], in: nil, in: .page, completionHandler: nil)
    }

    func received(_ message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        if message.name == "fwSync" {
            sync(body)
            return
        }
        if message.name == "fwDrive" {
            drive(body)
            return
        }
        if message.name == "fwTV" {
            if body == "ready" {
                tvReady = true
                if let latest = tvLatest { sendToTV(latest) }
                tellPhone()
            }
            return
        }
        if body == "hello" {
            tellPhone()
            return
        }
        tvLatest = body
        sendToTV(body)
    }

    // MARK: - Progress sync

    private func sync(_ json: String) {
        guard let data = json.data(using: .utf8),
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
        guard let web = phoneWebView else { return }
        var values: [String: String] = [:]
        for key in keys ?? syncKeys where syncKeys.contains(key) {
            if let value = cloud.string(forKey: key) { values[key] = value }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let json = String(data: data, encoding: .utf8) else { return }
        web.callAsyncJavaScript("if (window.__fwSyncIn) window.__fwSyncIn(JSON.parse(s));", arguments: ["s": json], in: nil, in: .page, completionHandler: nil)
    }

    // MARK: - Drive mode

    /// The page sends {"on": Bool, "title", "artist", "album", "playing": Bool} whenever Drive mode changes.
    private func drive(_ json: String) {
        guard let data = json.data(using: .utf8),
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let on = msg["on"] as? Bool ?? false
        if on != driveOn {
            driveOn = on
            if on { startDrive() } else { stopDrive() }
        }
        guard on else { return }
        let playing = msg["playing"] as? Bool ?? true
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: msg["title"] as? String ?? "Fretwise",
            MPMediaItemPropertyArtist: msg["artist"] as? String ?? "Fretwise Drive",
            MPMediaItemPropertyAlbumTitle: msg["album"] as? String ?? "Drive mode",
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let art = driveArtwork { info[MPMediaItemPropertyArtwork] = art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func startDrive() {
        configureDriveSession()
        let rc = MPRemoteCommandCenter.shared()
        if !driveCommandsAdded {
            _ = rc.nextTrackCommand.addTarget { [weak self] _ in self?.driveCommand("next"); return .success }
            _ = rc.previousTrackCommand.addTarget { [weak self] _ in self?.driveCommand("repeat"); return .success }
            _ = rc.playCommand.addTarget { [weak self] _ in self?.driveCommand("play"); return .success }
            _ = rc.pauseCommand.addTarget { [weak self] _ in self?.driveCommand("pause"); return .success }
            _ = rc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.driveCommand("toggle"); return .success }
            driveCommandsAdded = true
        }
        for cmd in [rc.nextTrackCommand, rc.previousTrackCommand, rc.playCommand, rc.pauseCommand, rc.togglePlayPauseCommand] { cmd.isEnabled = true }
        rc.skipForwardCommand.isEnabled = false
        rc.skipBackwardCommand.isEnabled = false
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    private func stopDrive() {
        let rc = MPRemoteCommandCenter.shared()
        for cmd in [rc.nextTrackCommand, rc.previousTrackCommand, rc.playCommand, rc.pauseCommand, rc.togglePlayPauseCommand] { cmd.isEnabled = false }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        UIApplication.shared.endReceivingRemoteControlEvents()
        configureAudioSession()
    }

    /// A car or headphone button, passed to the page: next, repeat, play, pause or toggle.
    private func driveCommand(_ cmd: String) {
        phoneWebView?.evaluateJavaScript("window.__fwDrive && window.__fwDrive('\(cmd)')", completionHandler: nil)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

}
