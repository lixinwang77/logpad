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
        let hasSelection = range.length > 0
        let activeColors = MarkCoordinator.shared.activeMarkColors()

        guard hasSelection || !activeColors.isEmpty else { return nil }

        let menu = NSMenu()

        if hasSelection {
            // Capture the selection now: opening the context menu can make this
            // view resign first responder before the menu action runs, so
            // reading it live there could come back empty.
            MarkCoordinator.shared.selectedText = (string as NSString).substring(with: range)
            let markItem = NSMenuItem(title: i18n.str("Mark"),
                                      action: #selector(markSelectedText(_:)), keyEquivalent: "")
            markItem.target = self
            menu.addItem(markItem)
        }

        if !activeColors.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }

            let removeItem = NSMenuItem(title: i18n.str("removeMark"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for color in activeColors {
                let item = NSMenuItem(title: i18n.str(color.localizedNameKey),
                                      action: #selector(removeMarkColorAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = color
                item.image = NonEditableTextView.swatch(for: color)
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
            let clearAll = NSMenuItem(title: i18n.str("clearAllMarks"),
                                      action: #selector(clearAllMarksAction(_:)), keyEquivalent: "")
            clearAll.target = self
            submenu.addItem(clearAll)

            removeItem.submenu = submenu
            menu.addItem(removeItem)
        }

        return menu
    }

    /// Small rounded color chip shown next to each color in the remove menu.
    private static func swatch(for color: HighlightColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        color.nsColor.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 2, yRadius: 2).fill()
        image.unlockFocus()
        return image
    }

    @objc func markSelectedText(_ sender: Any?) {
        if let selectedText = MarkCoordinator.shared.selectedText, !selectedText.isEmpty {
            onMarkText?(selectedText)
        }
    }

    @objc private func removeMarkColorAction(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? HighlightColor else { return }
        MarkCoordinator.shared.removeMarkColor(color)
    }

    @objc private func clearAllMarksAction(_ sender: Any?) {
        MarkCoordinator.shared.clearAllMarks()
    }
}
