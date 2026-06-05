import AppKit
import SwiftUI

/// Creates and tracks additional app windows and tabs. The first window is
/// created by SwiftUI's `WindowGroup`; every extra window/tab (Cmd+N / Cmd+T)
/// is an AppKit `NSWindow` hosting the same `ContentView`, so they share the
/// exact same UI while keeping fully independent `FileReader` / `SearchEngine`
/// state per window.
final class WindowManager {
    static let shared = WindowManager()

    /// Retains the controllers of windows we create so they stay alive until
    /// the user closes them (AppKit otherwise wouldn't keep a strong reference).
    private var controllers: [NSWindowController] = []

    private init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: ContentView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.title = "Logpad"
        window.isReleasedWhenClosed = false
        window.tabbingIdentifier = "LogpadMain"

        let controller = NSWindowController(window: window)
        controllers.append(controller)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.controllers.removeAll { $0.window === window }
        }
        return window
    }

    /// Cmd+N: open a brand-new, standalone window (never merged into a tab
    /// group). `tabbingMode` is forced off while we order it front so the
    /// system's "prefer tabs" setting can't auto-tab it onto the key window.
    func newWindow() {
        let window = makeWindow()
        window.tabbingMode = .disallowed
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.tabbingMode = .automatic
    }

    /// Cmd+T: open a new tab attached to the current key window's tab group.
    /// `addTabbedWindow` groups the windows regardless of tabbing mode; if
    /// there's no key window we just show it standalone.
    func newTab() {
        let window = makeWindow()
        if let key = NSApp.keyWindow {
            key.addTabbedWindow(window, ordered: .above)
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
}

/// Resolves the `NSWindow` hosting a SwiftUI view so each `MainView` can drive
/// its own window's title (instead of poking `NSApp.windows.first`, which is
/// wrong once more than one window/tab exists).
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

/// Holds a weak reference to a view's owning window so per-window title updates
/// and notification handlers can scope themselves to the right window. Kept as
/// a plain reference type (held via `@State`) so it never retains the window.
final class WindowHolder {
    weak var window: NSWindow?

    var isKey: Bool { window?.isKeyWindow ?? false }
}
