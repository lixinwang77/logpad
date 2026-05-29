import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        MainView()
            .onAppear {
                ShiftEnterMonitor.shared.start()
            }
            .onDisappear {
                ShiftEnterMonitor.shared.stop()
            }
    }
}

private struct WindowTitleAccessor: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}

extension View {
    func windowTitle(_ title: String) -> some View {
        background(WindowTitleAccessor(title: title))
    }
}

class ShiftEnterMonitor {
    static let shared = ShiftEnterMonitor()
    private var monitor: Any?

    func start() {
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
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

class MarkCoordinator {
    static let shared = MarkCoordinator()
    var selectedText: String?

    func requestMarkText() {
        if let text = selectedText, !text.isEmpty {
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowMarkMenu"),
                object: text
            )
        }
    }
}