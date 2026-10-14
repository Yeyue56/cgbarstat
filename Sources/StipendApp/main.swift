import AppKit
import StipendCore

/// LSUIElement 与 accessory 同时设置，应用不进入 Dock。
@main
enum StipendMain {
    @MainActor
    private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var menuBar: MenuBarController?
    private var refresher: RefreshLoop?
    private let redirects = RefuseRedirects()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
        let model = AppModel(
            store: UserDefaultsSnapshotStore(),
            reader: CursorSessionReader(),
            client: PeriodUsageClient(http: URLSessionHTTP(session: session))
        )
        self.model = model
        menuBar = MenuBarController(model: model)
        let refresher = RefreshLoop(model: model)
        refresher.start()
        self.refresher = refresher
    }
}
