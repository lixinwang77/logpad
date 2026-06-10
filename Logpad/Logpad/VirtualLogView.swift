import SwiftUI
import AppKit

/// Virtualized log renderer backed by `NSTableView`, which recycles a small
/// pool of row views regardless of total line count. This keeps memory and
/// view count bounded for very large files (vs. building one view per line).
struct VirtualLogView: NSViewRepresentable {
    @ObservedObject var fileReader: FileReader
    @ObservedObject var searchEngine: SearchEngine
    @Binding var targetLine: Int?
    var onTextSelected: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .textBackgroundColor
        tableView.rowHeight = 18
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = []
        tableView.selectionHighlightStyle = .none
        tableView.usesAutomaticRowHeights = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnResizing = false
        tableView.allowsColumnReordering = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        column.width = 1000
        tableView.addTableColumn(column)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.tableView = tableView

        scrollView.documentView = tableView

        // Continuously track the top visible line so a reload can restore it.
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: .main
        ) { [weak coord = context.coordinator] _ in
            guard let coord, let tv = coord.tableView else { return }
            let visible = tv.rows(in: tv.visibleRect)
            if visible.length > 0 {
                coord.topVisibleLine = visible.location + 1
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        guard let tableView = coord.tableView else { return }

        let total = fileReader.totalLines
        let containerWidth = scrollView.contentSize.width

        // A reload (not a fresh open) bumps reloadGeneration; capture the current
        // top line before the upcoming re-index resets the table, so we can
        // restore it once the new line count arrives.
        if coord.lastReloadGeneration != fileReader.reloadGeneration {
            coord.lastReloadGeneration = fileReader.reloadGeneration
            coord.pendingRestoreLine = coord.topVisibleLine
        }

        if coord.lastTotalLines != total {
            coord.lastTotalLines = total
            coord.recomputeWidth(containerWidth: containerWidth)
            tableView.tableColumns.first?.width = coord.contentWidth
            tableView.reloadData()
            if total > 0 {
                if let restore = coord.pendingRestoreLine {
                    coord.pendingRestoreLine = nil
                    coord.scrollRowToTop(min(max(restore - 1, 0), total - 1))
                } else {
                    tableView.scrollRowToVisible(0)
                    scrollView.contentView.scroll(to: .zero)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        } else if coord.lastRevision != searchEngine.revision {
            // Highlights changed: refresh only the rows currently on screen.
            let visible = tableView.rows(in: tableView.visibleRect)
            if visible.length > 0 {
                let rows = IndexSet(integersIn: visible.location..<(visible.location + visible.length))
                tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
            }
        }
        coord.lastRevision = searchEngine.revision

        // Keep the column at least as wide as the viewport.
        if let column = tableView.tableColumns.first, column.width < containerWidth {
            column.width = max(coord.contentWidth, containerWidth)
        }

        if let line = targetLine, total > 0 {
            let row = min(max(line - 1, 0), total - 1)
            coord.scrollRowToTop(row)
            DispatchQueue.main.async { self.targetLine = nil }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: VirtualLogView
        weak var tableView: NSTableView?
        var lastTotalLines = -1
        var lastRevision = -1
        var contentWidth: CGFloat = 1000
        /// 1-based line currently at the top of the viewport, kept in sync via
        /// the scroll bounds observer.
        var topVisibleLine = 1
        /// Top line to restore after a reload-triggered re-index completes.
        var pendingRestoreLine: Int?
        var lastReloadGeneration = 0
        var boundsObserver: NSObjectProtocol?

        private static let rowIdentifier = NSUserInterfaceItemIdentifier("LogRowView")
        private static let measureFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        init(_ parent: VirtualLogView) {
            self.parent = parent
        }

        deinit {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        }

        func recomputeWidth(containerWidth: CGFloat) {
            let total = parent.fileReader.totalLines
            let sample = min(total, 100)
            var maxWidth = containerWidth
            for i in 0..<sample {
                let content = parent.fileReader.readLine(at: i) ?? ""
                let width = (content as NSString).size(withAttributes: [.font: Coordinator.measureFont]).width + 70
                if width > maxWidth { maxWidth = width }
            }
            contentWidth = max(maxWidth, containerWidth)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.fileReader.totalLines
        }

        /// Scrolls so the given row sits at the top of the viewport (clamped so
        /// we never scroll past the end of the document). Horizontal offset is
        /// preserved.
        func scrollRowToTop(_ row: Int) {
            guard let tableView, let scrollView = tableView.enclosingScrollView else { return }
            let rowRect = tableView.rect(ofRow: row)
            let clip = scrollView.contentView
            let maxOriginY = max(0, tableView.bounds.height - clip.bounds.height)
            var origin = clip.bounds.origin
            origin.y = min(max(rowRect.minY, 0), maxOriginY)
            clip.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clip)
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let view: LogRowView
            if let reused = tableView.makeView(withIdentifier: Coordinator.rowIdentifier, owner: self) as? LogRowView {
                view = reused
            } else {
                view = LogRowView()
                view.identifier = Coordinator.rowIdentifier
            }

            let content = parent.fileReader.readLine(at: row) ?? ""
            let lineID = row + 1
            let currentRange = lineID == parent.searchEngine.currentMatchLineID
                ? parent.searchEngine.currentMatchRange
                : nil
            view.configure(
                lineNumber: lineID,
                content: content,
                searchRanges: parent.searchEngine.searchRanges(forLineID: lineID),
                currentSearchRange: currentRange,
                markRanges: parent.searchEngine.markRanges(in: content),
                onMarkText: parent.onTextSelected
            )
            return view
        }
    }
}

/// A recycled row: a right-aligned line-number gutter plus a selectable,
/// single-line text view that renders search/mark highlights.
final class LogRowView: NSView {
    private let lineLabel = NSTextField(labelWithString: "")
    private let textView = NonEditableTextView(frame: .zero)
    private let gutterWidth: CGFloat = 50

    private static let lineFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let contentFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    /// Paragraph style applied to every row. Without explicit tab handling, a
    /// TAB that lands past the default tab stops (common in indented stack
    /// traces) makes the single-line layout drop everything after it. Clearing
    /// the stops, using a fixed interval, and clipping (not truncating) keeps
    /// the full line — tabs included — visible.
    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byClipping
        style.tabStops = []
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: contentFont]).width
        style.defaultTabInterval = max(spaceWidth * 4, 1)
        return style
    }()
    /// Background for ordinary search matches and the currently focused one.
    static let searchColor = NSColor.systemYellow
    static let currentSearchColor = NSColor.systemYellow.blended(withFraction: 0.5, of: .systemOrange) ?? .systemOrange

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        lineLabel.font = LogRowView.lineFont
        lineLabel.textColor = .secondaryLabelColor
        lineLabel.alignment = .right
        lineLabel.isBezeled = false
        lineLabel.drawsBackground = false
        lineLabel.isEditable = false
        lineLabel.isSelectable = false
        addSubview(lineLabel)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.maximumNumberOfLines = 1
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 18)
        textView.minSize = NSSize(width: 0, height: 18)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        lineLabel.frame = NSRect(x: 0, y: 0, width: gutterWidth - 8, height: bounds.height)
        textView.frame = NSRect(x: gutterWidth, y: 0, width: max(bounds.width - gutterWidth, 0), height: bounds.height)
    }

    func configure(lineNumber: Int,
                   content: String,
                   searchRanges: [NSRange],
                   currentSearchRange: NSRange?,
                   markRanges: [(NSRange, HighlightColor)],
                   onMarkText: ((String) -> Void)?) {
        lineLabel.stringValue = "\(lineNumber)"
        textView.onMarkText = onMarkText

        let attributed = NSMutableAttributedString(string: content)
        let nsLength = (content as NSString).length
        let fullRange = NSRange(location: 0, length: nsLength)
        attributed.addAttribute(.font, value: LogRowView.contentFont, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        attributed.addAttribute(.paragraphStyle, value: LogRowView.paragraphStyle, range: fullRange)

        for (range, color) in markRanges where range.location >= 0 && range.location + range.length <= nsLength {
            attributed.addAttribute(.backgroundColor,
                                    value: color.nsColor.withAlphaComponent(0.5),
                                    range: range)
        }

        for searchRange in searchRanges where searchRange.location >= 0
            && searchRange.location + searchRange.length <= nsLength {
            let isCurrent = currentSearchRange.map { NSEqualRanges($0, searchRange) } ?? false
            attributed.addAttribute(.backgroundColor,
                                    value: isCurrent ? LogRowView.currentSearchColor : LogRowView.searchColor,
                                    range: searchRange)
        }

        textView.textStorage?.setAttributedString(attributed)
    }
}
