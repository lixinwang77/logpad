import SwiftUI
import AppKit

struct ContentView: View {
    @State private var showAbout = false

    var body: some View {
        MainView()
            .onAppear {
                ShiftEnterMonitor.shared.start()
            }
            .onDisappear {
                ShiftEnterMonitor.shared.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowAbout"))) { _ in
                showAbout = true
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
    }
}

extension Notification.Name {
    static let windowTitleChanged = Notification.Name("WindowTitleChanged")
}

class ShiftEnterMonitor {
    static let shared = ShiftEnterMonitor()
    private var monitor: Any?
    /// Each window's ContentView calls start/stop; the single shared monitor is
    /// installed once and only removed when the last window goes away. This
    /// avoids stacking duplicate monitors (which would post SearchPrevious
    /// multiple times per keystroke) across multiple windows/tabs.
    private var refCount = 0

    func start() {
        refCount += 1
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("SearchPrevious"),
                    object: nil
                )
                return nil
            }
            return event
        }
    }

    func stop() {
        refCount = max(0, refCount - 1)
        guard refCount == 0, let monitor = monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

class MarkCoordinator {
    static let shared = MarkCoordinator()
    var selectedText: String?

    /// Bridges the recycled log text views to the mark state in `SearchEngine`
    /// (wired by `MainView`), so the right-click menu can list active colors
    /// and remove marks without holding a reference to the engine.
    var activeMarkColors: () -> [HighlightColor] = { [] }
    var removeMarkColor: (HighlightColor) -> Void = { _ in }
    var removeMarkText: (String) -> Void = { _ in }
    var clearAllMarks: () -> Void = {}

    func requestMarkText() {
        if let text = selectedText, !text.isEmpty {
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowMarkMenu"),
                object: text
            )
        }
    }

    /// Cmd+Shift+M: remove the mark for the currently selected text.
    func requestRemoveMarkText() {
        if let text = selectedText, !text.isEmpty {
            removeMarkText(text)
        }
    }
}