import AppKit

/// Tracks the single log row that currently owns a text selection. When focus
/// moves to another row, the previously active row's selection is cleared so it
/// doesn't linger as a gray (inactive) selection box. Only ever clears the
/// *other* row, never the one being interacted with, so the Mark flow (which
/// reads the focused row's selection) is unaffected.
final class SelectionCoordinator {
    static let shared = SelectionCoordinator()
    private weak var active: NonEditableTextView?

    func setActive(_ view: NonEditableTextView) {
        guard active !== view else { return }
        active?.setSelectedRange(NSRange(location: 0, length: 0))
        active = view
    }
}

/// Single-line, non-editable text view used as a recycled row in the
/// virtualized log table. Supports text selection, a "Mark" context menu, and
/// reports the selected text to `MarkCoordinator` for the Cmd+M flow.
class NonEditableTextView: NSTextView {
    var onMarkText: ((String) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        SelectionCoordinator.shared.setActive(self)
        updateSelectedText()
        return result
    }

    private func updateSelectedText() {
        let range = selectedRange()
        if range.length > 0 {
            let selectedText = (string as NSString).substring(with: range)
            MarkCoordinator.shared.selectedText = selectedText
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        updateSelectedText()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        updateSelectedText()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let range = selectedRange()
        guard range.length > 0 else { return nil }

        // Capture the selection now: opening the context menu can make this view
        // resign first responder before the menu action runs, so reading it live
        // there could come back empty.
        MarkCoordinator.shared.selectedText = (string as NSString).substring(with: range)

        let menu = NSMenu()
        let markItem = NSMenuItem(title: "Mark", action: #selector(markSelectedText(_:)), keyEquivalent: "")
        markItem.target = self
        menu.addItem(markItem)
        return menu
    }

    @objc func markSelectedText(_ sender: Any?) {
        if let selectedText = MarkCoordinator.shared.selectedText, !selectedText.isEmpty {
            onMarkText?(selectedText)
        }
    }
}
