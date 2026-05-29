import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @StateObject private var fileReader = FileReader()
    @StateObject private var searchEngine = SearchEngine()
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var splitMode: SplitMode = .none
    @State private var filterCondition = FilterCondition()
    @State private var selectedLine: Int?
    @State private var targetLine: Int?
    @State private var showFilePicker = false
    @State private var langKey: Int = 0
    @State private var isSearchFieldFocused = false
    @State private var currentSearchIndex = 0
    @State private var highlightMarks: [HighlightMark] = []
    @State private var showMarkMenu = false
    @State private var pendingMarkText = ""
    @State private var showGoToLine = false
    @State private var goToLineInput = ""

    var body: some View {
        Group {
            if let error = fileReader.error {
                ErrorView(message: error) {
                    showFilePicker = true
                }
            } else if fileReader.totalLines == 0 && !fileReader.isLoading {
                EmptyFileView {
                    showFilePicker = true
                }
            } else {
                mainContent
            }
        }
        .id("lang-\(langKey)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.plainText, .log],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    _ = url.startAccessingSecurityScopedResource()
                    fileReader.open(url: url)
                }
            case .failure(let error):
                fileReader.error = error.localizedDescription
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let item = providers.first else { return false }
            item.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    _ = url.startAccessingSecurityScopedResource()
                    DispatchQueue.main.async {
                        fileReader.open(url: url)
                    }
                }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenDocument"))) { _ in
            showFilePicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusSearchField"))) { _ in
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GoToLine"))) { _ in
            guard fileReader.totalLines > 0, !fileReader.isLoading else { return }
            goToLineInput = ""
            showGoToLine = true
        }
        .sheet(isPresented: $showGoToLine) {
            GoToLineView(
                lineInput: $goToLineInput,
                totalLines: fileReader.totalLines,
                onGo: { line in
                    targetLine = line
                    showGoToLine = false
                },
                onCancel: {
                    showGoToLine = false
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SearchPrevious"))) { _ in
            jumpToPreviousResult()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowMarkMenu"))) { notification in
            if let text = notification.object as? String, !text.isEmpty {
                pendingMarkText = text
                showMarkMenu = true
            }
        }
    }

    private func performSearch() {
        searchEngine.search(condition: filterCondition, totalLines: fileReader.totalLines) { lineNumber in
            fileReader.readLine(at: lineNumber)
        } onComplete: { [self] in
            currentSearchIndex = 0
            if let first = searchEngine.results.first {
                targetLine = first.line.id
            }
        }
    }

    private func submitOrNext() {
        if searchEngine.results.isEmpty && !filterCondition.keyword.isEmpty {
            performSearch()
        } else {
            jumpToNextResult()
        }
    }

    private func jumpToNextResult() {
        guard !searchEngine.results.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchEngine.results.count
        targetLine = searchEngine.results[currentSearchIndex].line.id
    }

    private func jumpToPreviousResult() {
        guard !searchEngine.results.isEmpty else { return }
        currentSearchIndex = currentSearchIndex > 0 ? currentSearchIndex - 1 : searchEngine.results.count - 1
        targetLine = searchEngine.results[currentSearchIndex].line.id
    }

    private func addHighlightMark(text: String, color: HighlightColor) {
        let mark = HighlightMark(text: text, color: color)
        highlightMarks.append(mark)
        searchEngine.searchMarks(highlightMarks, totalLines: fileReader.totalLines) { lineNumber in
            fileReader.readLine(at: lineNumber)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            ToolbarView(
                splitMode: $splitMode,
                filterCondition: $filterCondition,
                isSearching: searchEngine.isSearching,
                onOpenFile: { showFilePicker = true },
                onSearchSubmit: { submitOrNext() },
                langKey: $langKey,
                isSearchFieldFocused: $isSearchFieldFocused
            )

            Divider()

            if splitMode == .none {
                LogContentView(
                    fileReader: fileReader,
                    searchEngine: searchEngine,
                    targetLine: $targetLine,
                    onTextSelected: { text in
                        pendingMarkText = text
                        showMarkMenu = true
                    }
                )
            } else if splitMode == .vertical {
                HSplitView {
                    LogContentView(
                        fileReader: fileReader,
                        searchEngine: searchEngine,
                        targetLine: $targetLine,
                        onTextSelected: { text in
                            pendingMarkText = text
                            showMarkMenu = true
                        }
                    )
                    FilterResultView(
                        results: searchEngine.results,
                        onLineSelected: { line in
                            targetLine = line.id
                        }
                    )
                }
            } else {
                VStack(spacing: 0) {
                    LogContentView(
                        fileReader: fileReader,
                        searchEngine: searchEngine,
                        targetLine: $targetLine,
                        onTextSelected: { text in
                            pendingMarkText = text
                            showMarkMenu = true
                        }
                    )
                    Divider()
                    FilterResultView(
                        results: searchEngine.results,
                        onLineSelected: { line in
                            targetLine = line.id
                        }
                    )
                }
            }
        }
        .onChange(of: filterCondition) { _, newCondition in
            searchEngine.search(condition: newCondition, totalLines: fileReader.totalLines) { lineNumber in
                fileReader.readLine(at: lineNumber)
            }
        }
        .sheet(isPresented: $showMarkMenu) {
            MarkMenuView(text: pendingMarkText) { color in
                addHighlightMark(text: pendingMarkText, color: color)
                showMarkMenu = false
            }
        }
    }
}

struct LogContentView: View {
    @ObservedObject var fileReader: FileReader
    @ObservedObject var searchEngine: SearchEngine
    @Binding var targetLine: Int?
    var onTextSelected: ((String) -> Void)?

    private let lineHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let total = fileReader.totalLines

                        if total > 0 {
                            ForEach(0..<total, id: \.self) { row in
                                SelectableLogView(
                                    lineNumber: row + 1,
                                    content: fileReader.readLine(at: row) ?? "",
                                    searchHighlightRange: searchEngine.results.first { $0.line.id == row + 1 }?.highlightRange,
                                    markRanges: searchEngine.markResults[row],
                                    onMarkText: onTextSelected
                                )
                                .id(row + 1)
                            }
                        }
                    }
                    .frame(width: maxContentWidth(in: geo.size.width), alignment: .leading)
                }
                .onChange(of: targetLine) { _, newLine in
                    if let line = newLine {
                        withAnimation {
                            proxy.scrollTo(line, anchor: .topLeading)
                        }
                        targetLine = nil
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FileDidLoad"))) { _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo(0, anchor: .top)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(0, anchor: .leading)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func maxContentWidth(in containerWidth: CGFloat) -> CGFloat {
        var maxWidth = containerWidth
        let total = fileReader.totalLines
        let sampleCount = min(total, 100)
        for i in 0..<sampleCount {
            let content = fileReader.readLine(at: i) ?? ""
            let width = estimateTextWidth(content)
            if width > maxWidth {
                maxWidth = width
            }
        }
        return max(maxWidth, containerWidth)
    }

    private func estimateTextWidth(_ text: String) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return size.width + 58
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct LogLineRow: View {
    let lineNumber: Int
    let content: String
    let highlightRange: Range<String.Index>?
    let markRanges: [(Range<String.Index>, HighlightColor)]?
    let onMarkText: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Text("\(lineNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, 8)

            highlightedContent
        }
        .padding(.vertical, 1)
        .textSelection(.enabled)
        .onTapGesture(count: 2) {
            // Double-click to select word and show mark menu
            if let pasteboard = NSPasteboard.general.string(forType: .string),
               !pasteboard.isEmpty {
                onMarkText?(pasteboard)
            }
        }
        .contextMenu {
            Button("Mark") {
                if let pasteboard = NSPasteboard.general.string(forType: .string),
                   !pasteboard.isEmpty {
                    onMarkText?(pasteboard)
                }
            }
        }
    }

    private var highlightedContent: some View {
        let contentLength = content.count
        var ranges: [(Int, Int, HighlightColor?)] = []  // (start, end, color) - nil means yellow search highlight

        // Add mark highlights
        if let marks = markRanges {
            for (range, color) in marks {
                let start = content.distance(from: content.startIndex, to: range.lowerBound)
                let end = content.distance(from: content.startIndex, to: range.upperBound)
                ranges.append((start, end, color))
            }
        }

        // Add search highlight (yellow)
        if let searchRange = highlightRange {
            let start = content.distance(from: content.startIndex, to: searchRange.lowerBound)
            let end = content.distance(from: content.startIndex, to: searchRange.upperBound)
            ranges.append((start, end, nil))
        }

        if ranges.isEmpty {
            return AnyView(Text(content).font(.system(size: 13, design: .monospaced)))
        }

        // Sort ranges by start position
        ranges.sort { $0.0 < $1.0 }

        // Build text segments as AttributedString for proper concatenation
        var attributedString = AttributedString(content)

        for (start, end, color) in ranges {
            guard start >= 0, end <= contentLength, start < end else { continue }

            let startIndex = content.index(content.startIndex, offsetBy: start)
            let endIndex = content.index(content.startIndex, offsetBy: end)

            if let attrRange = Range(startIndex..<endIndex, in: attributedString) {
                attributedString[attrRange].backgroundColor = color?.nsColor.withAlphaComponent(0.5) ?? NSColor.systemYellow
            }
        }

        return AnyView(Text(attributedString).font(.system(size: 13, design: .monospaced)))
    }
}

struct ToolbarView: View {
    @Binding var splitMode: SplitMode
    @Binding var filterCondition: FilterCondition
    let isSearching: Bool
    let onOpenFile: () -> Void
    let onSearchSubmit: () -> Void
    @Binding var langKey: Int
    @Binding var isSearchFieldFocused: Bool

    var body: some View {
        HStack {
            Button(action: onOpenFile) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)

            Divider().frame(height: 20)

            SearchFieldView(
                text: $filterCondition.keyword,
                isTextFieldFocused: isSearchFieldFocused,
                onSubmit: onSearchSubmit
            )
            .frame(width: 180)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .onChange(of: isSearchFieldFocused) { _, newValue in
                if newValue {
                    isSearchFieldFocused = false
                }
            }

            Toggle(i18n.str("Regex"), isOn: $filterCondition.isRegex)
                .toggleStyle(.checkbox)

            Toggle("Aa", isOn: $filterCondition.isCaseSensitive)
                .toggleStyle(.checkbox)

            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Spacer()

            HStack(spacing: 4) {
                Button {
                    splitMode = .none
                } label: {
                    Image(systemName: "rectangle")
                }
                .buttonStyle(.borderless)
                .foregroundColor(splitMode == .none ? .accentColor : .secondary)

                Button {
                    splitMode = .vertical
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .buttonStyle(.borderless)
                .foregroundColor(splitMode == .vertical ? .accentColor : .secondary)

                Button {
                    splitMode = .horizontal
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                }
                .buttonStyle(.borderless)
                .foregroundColor(splitMode == .horizontal ? .accentColor : .secondary)
            }

            Spacer()

            Menu {
                Button("English") {
                    LanguageManager.shared.setLanguage("en")
                    langKey += 1
                }
                Button("中文") {
                    LanguageManager.shared.setLanguage("zh-Hans")
                    langKey += 1
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "globe")
                    Text(LanguageManager.shared.currentLanguage == "zh-Hans" ? "中文" : "EN")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

struct FilterResultView: View {
    let results: [FilterResult]
    let onLineSelected: (LogLine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(i18n.str("Results")): \(results.count)")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if results.isEmpty {
                Spacer()
                Text(i18n.str("No results"))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { result in
                            Button {
                                onLineSelected(result.line)
                            } label: {
                                HStack(alignment: .top, spacing: 0) {
                                    Text("\(result.line.id)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 50, alignment: .trailing)
                                        .padding(.trailing, 6)

                                    Text(result.line.content)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .textSelection(.enabled)

                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 200)
    }
}

struct EmptyFileView: View {
    let onOpenFile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(i18n.str("No file open"))
                .font(.headline)
            Text(i18n.str("dragDropHint"))
                .foregroundColor(.secondary)
            Button(i18n.str("openFile")) {
                onOpenFile()
            }
        }
    }
}

struct SearchFieldView: View {
    @Binding var text: String
    let isTextFieldFocused: Bool
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(i18n.str("Search..."), text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    onSubmit()
                }
        }
        .onChange(of: isTextFieldFocused) { _, newValue in
            if newValue {
                focused = true
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(message)
                .foregroundColor(.secondary)
            Button(i18n.str("tryAgain")) {
                onRetry()
            }
        }
    }
}

struct GoToLineView: View {
    @Binding var lineInput: String
    let totalLines: Int
    let onGo: (Int) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool
    @State private var showInvalidHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(i18n.str("Go to Line"))
                .font(.headline)

            TextField(i18n.str("Line number:"), text: $lineInput)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(submit)
                .onChange(of: lineInput) { _, _ in
                    showInvalidHint = false
                }

            Text(String(format: i18n.str("lineRangeHint"), totalLines))
                .font(.caption)
                .foregroundColor(.secondary)

            if showInvalidHint {
                Text(String(format: i18n.str("invalidLineNumber"), totalLines))
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(i18n.str("Cancel"), role: .cancel, action: onCancel)
                Button(i18n.str("Go"), action: submit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            isFocused = true
        }
    }

    private func submit() {
        let trimmed = lineInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(trimmed), number >= 1, number <= totalLines else {
            showInvalidHint = true
            return
        }
        onGo(number)
    }
}

struct MarkMenuView: View {
    let text: String
    let onSelect: (HighlightColor) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Select highlight color for:")
                .font(.headline)
            Text("\"\(text)\"")
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

            HStack(spacing: 12) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button {
                        onSelect(color)
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 30, height: 30)
                    }
                }
            }
        }
        .padding()
        .frame(width: 300)
    }
}