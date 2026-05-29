import AppKit

/// Single-line, non-editable text view used as a recycled row in the
/// virtualized log table. Supports text selection, a "Mark" context menu, and
/// reports the selected text to `MarkCoordinator` for the Cmd+M flow.
class NonEditableTextView: NSTextView {
    var onMarkText: ((String) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
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
        let menu = NSMenu()

        if selectedRange().length > 0 {
            let markItem = NSMenuItem(title: "Mark", action: #selector(markSelectedText(_:)), keyEquivalent: "")
            markItem.target = self
            menu.addItem(markItem)
        }

        return menu
    }

    @objc func markSelectedText(_ sender: Any?) {
        let range = selectedRange()
        let selectedText = (string as NSString).substring(with: range)
        if !selectedText.isEmpty {
            onMarkText?(selectedText)
        }
    }
}
