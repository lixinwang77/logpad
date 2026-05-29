import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SelectableLogView: View {
    let lineNumber: Int
    let content: String
    let searchHighlightRange: Range<String.Index>?
    let markRanges: [(Range<String.Index>, HighlightColor)]?
    var onMarkText: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Text("\(lineNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, 8)

            LogTextViewRepresentable(
                content: content,
                searchHighlightRange: searchHighlightRange,
                markRanges: markRanges,
                onMarkText: onMarkText
            )
        }
        .frame(height: 18)
        .padding(.vertical, 1)
    }
}

struct LogTextViewRepresentable: NSViewRepresentable {
    let content: String
    let searchHighlightRange: Range<String.Index>?
    let markRanges: [(Range<String.Index>, HighlightColor)]?
    var onMarkText: ((String) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true

        let textView = NonEditableTextView(frame: .zero)
        textView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        textView.onMarkText = onMarkText

        context.coordinator.textView = textView
        updateTextContent(textView)

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        updateTextContent(textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func updateTextContent(_ textView: NonEditableTextView) {
        let attributedString = createAttributedContent()
        textView.textStorage?.setAttributedString(attributedString)
    }

    private func createAttributedContent() -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let attributedString = NSMutableAttributedString(string: content)
        attributedString.addAttribute(.font, value: font, range: NSRange(location: 0, length: content.count))
        attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: content.count))

        if let marks = markRanges {
            for (range, color) in marks {
                let start = content.distance(from: content.startIndex, to: range.lowerBound)
                let end = content.distance(from: content.startIndex, to: range.upperBound)
                if start >= 0 && end <= content.count && start < end {
                    let nsRange = NSRange(location: start, length: end - start)
                    attributedString.addAttribute(.backgroundColor, value: color.nsColor.withAlphaComponent(0.5), range: nsRange)
                }
            }
        }

        if let searchRange = searchHighlightRange {
            let start = content.distance(from: content.startIndex, to: searchRange.lowerBound)
            let end = content.distance(from: content.startIndex, to: searchRange.upperBound)
            if start >= 0 && end <= content.count && start < end {
                let nsRange = NSRange(location: start, length: end - start)
                attributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: nsRange)
            }
        }

        return attributedString
    }

    class Coordinator {
        weak var textView: NonEditableTextView?
    }
}

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