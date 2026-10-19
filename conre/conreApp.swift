import SwiftUI
import AppKit

@main
struct conreApp: App {
    @NSApplicationDelegateAdaptor(ConreAppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class ConreAppDelegate: NSObject, NSApplicationDelegate {
    private lazy var memory = WorkingMemoryStore()
    private lazy var observer = ActivityObserver()
    private lazy var appearance = StatusAppearance()
    private lazy var summary = SummaryController()
    private lazy var assistant = WorkAssistant(observer: observer, summary: summary)
    private let floatingStatus = FloatingStatusController()
    private var window: NSWindow?
    private var migrationMessage: String?
    override init() {
        super.init()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
           NSClassFromString("XCTestCase") == nil {
            migrationMessage = LegacyStorageMigration.prepare()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        observer.start()
        assistant.start()
        floatingStatus.show(observer: observer, appearance: appearance, assistant: assistant) { [weak self] in self?.showMainWindow() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) { assistant.stop(); observer.stop() }
    private func showMainWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Conre"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView(memory: memory, observer: observer, appearance: appearance, migrationMessage: migrationMessage, assistant: assistant))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
