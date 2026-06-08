import AppKit
import SwiftUI

/// Queues file URLs passed by Finder (double-click / Open With) until a
/// `MainView` is ready to consume them. Handles cold-launch ordering where
/// `application(_:open:)` may arrive before the first window exists.
final class ExternalFileOpener {
    static let shared = ExternalFileOpener()
    static let notification = Notification.Name("OpenExternalFile")

    private var pendingURL: URL?
    private var pendingByWindow: [ObjectIdentifier: URL] = [:]
    private(set) var lastAssignedTargetWindow: NSWindow?

    func open(_ url: URL) {
        DispatchQueue.main.async {
            self.deliver(url)
        }
    }

    private func deliver(_ url: URL) {
        let visibleWindows = NSApp.windows.filter(\.isVisible)
        if visibleWindows.isEmpty {
            pendingURL = url
            NotificationCenter.default.post(name: Self.notification, object: url)
            return
        }

        // Bring the app forward so window/tab operations behave as if frontmost
        // (Finder's "Open With" leaves us in the background).
        NSApp.activate(ignoringOtherApps: true)

        // A window already showing a file (title != app name) means the app is
        // in active use: add the new file as a tab on that window's group. Only
        // when there's no such window (cold launch) do we reuse the initial
        // empty WindowGroup window instead of spawning an extra tab.
        let target: NSWindow
        if let busy = visibleWindows.first(where: { $0.title != "Logpad" }) {
            target = WindowManager.shared.openInNewTab(attachingTo: busy)
        } else {
            target = visibleWindows.first ?? WindowManager.shared.openInNewTab()
            target.makeKeyAndOrderFront(nil)
        }
        lastAssignedTargetWindow = target
        assign(url: url, to: target)
        schedulePrune()
    }

    func assign(url: URL, to window: NSWindow) {
        pendingByWindow[ObjectIdentifier(window)] = url
        NotificationCenter.default.post(name: Self.notification, object: url)
    }

    func takePending(for window: NSWindow?, isKey: Bool, hasOpenFile: Bool) -> URL? {
        if let window, let url = pendingByWindow.removeValue(forKey: ObjectIdentifier(window)) {
            return url
        }
        guard let url = pendingURL else { return nil }
        let soleVisibleWindow = NSApp.windows.filter(\.isVisible).count <= 1
        guard isKey || (!hasOpenFile && soleVisibleWindow) else { return nil }
        pendingURL = nil
        return url
    }

    /// macOS window-state restoration can recreate several empty `WindowGroup`
    /// windows on launch (SwiftUI restores blank `ContentView`s, since the open
    /// file isn't part of its saved state), and Finder "Open With" can spawn an
    /// extra one. Restored windows may appear a beat apart, so sweep a few times.
    func schedulePrune() {
        for delay in [0.0, 0.3, 0.7, 1.2, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.pruneIdleWindows()
            }
        }
    }

    /// Keeps at most one idle (no file open) standalone window: closes the rest,
    /// and closes all of them when any window already shows a file. The window
    /// currently receiving a file (`lastAssignedTargetWindow`) is never closed.
    private func pruneIdleWindows() {
        let target = lastAssignedTargetWindow
        let visible = NSApp.windows.filter(\.isVisible)

        let hasFileWindow = visible.contains { $0.title != "Logpad" || $0 === target }
        let idleStandalone = visible.filter { window in
            window !== target
                && window.title == "Logpad"
                && (window.tabbedWindows?.count ?? 1) <= 1
        }

        var closedAny = false
        for (index, window) in idleStandalone.enumerated() {
            // When no file is shown anywhere, keep a single guide-page window.
            if !hasFileWindow && index == 0 { continue }
            window.close()
            closedAny = true
        }
        if closedAny, let target, target.isVisible {
            target.makeKeyAndOrderFront(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Stop macOS from restoring (blank) windows on next launch; restored
        // WindowGroup windows would otherwise pile up as empty guide pages.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ExternalFileOpener.shared.schedulePrune()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        ExternalFileOpener.shared.open(url)
    }
}

@main
struct LogpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("\(i18n.str("About")) \(AppVersion.appName)...") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ShowAbout"),
                        object: nil
                    )
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(i18n.str("New Window")) {
                    WindowManager.shared.newWindow()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(i18n.str("New Tab")) {
                    WindowManager.shared.newTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                Button("Open...") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenDocument"),
                        object: nil
                    )
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Find") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FocusSearchField"),
                        object: nil
                    )
                }
                .keyboardShortcut("f", modifiers: .command)

                Button(i18n.str("Go to Line")) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GoToLine"),
                        object: nil
                    )
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Mark") {
                    MarkCoordinator.shared.requestMarkText()
                }
                .keyboardShortcut("m", modifiers: .command)

                Button(i18n.str("removeMark")) {
                    MarkCoordinator.shared.requestRemoveMarkText()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}
