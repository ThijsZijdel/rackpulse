import AppKit
import SwiftUI

@main
@MainActor
enum RackpulseApp {
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ProjectStore()
    private let settings = SettingsStore()
    private let updates = Updates()
    private let actions = AppActions()
    private var monitor: Monitor!
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindow!
    private let shortcut = GlobalShortcut()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
        monitor = Monitor(store: store, settings: settings)
        let store = store, monitor = monitor!, settings = settings, actions = actions, updates = updates
        settingsWindow = SettingsWindow {
            AnyView(SettingsView(store: store, monitor: monitor, settings: settings, updates: updates).environment(actions))
        }
        actions.showSettings = { [weak self] in
            self?.statusBar.close()
            self?.settingsWindow.show()
        }
        statusBar = StatusBarController(store: store, monitor: monitor, updates: updates, actions: actions)
        monitor.notifier.onOpen = { [weak self] in self?.statusBar.show() }
        GlobalShortcut.action = { [weak self] in self?.statusBar.toggle() }
        shortcut.apply(settings.value.shortcut)
        actions.shortcutChanged = { [weak self] in
            guard let self else { return }
            shortcut.apply(settings.value.shortcut)
        }
        if let path = ProcessInfo.processInfo.environment["RACKPULSE_SNAPSHOTS"] {
            let snapshots = Snapshots(
                folder: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent(path), monitor: monitor, store: store, settings: settings,
                actions: actions, statusBar: statusBar, settingsWindow: settingsWindow
            )
            Task { await snapshots.run() }
        }
    }

    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Rackpulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
