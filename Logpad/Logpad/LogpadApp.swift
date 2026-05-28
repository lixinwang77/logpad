import SwiftUI

@main
struct LogpadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
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
            }
        }
    }
}
