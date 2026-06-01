import SwiftUI

@main
struct LogpadApp: App {
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
