import SwiftUI

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