import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @StateObject private var fileReader = FileReader()
    @StateObject private var searchEngine = SearchEngine()
    @State private var windowHolder = WindowHolder()
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var splitMode: SplitMode = .none
    @State private var filterCondition = FilterCondition(
        isRegex: UserDefaults.standard.bool(forKey: MainView.regexDefaultsKey),
        isCaseSensitive: UserDefaults.standard.bool(forKey: MainView.caseSensitiveDefaultsKey)
    )

    /// UserDefaults keys for persisting the search option toggles so they
    /// survive app relaunches (the keyword itself stays transient).
    private static let regexDefaultsKey = "filterIsRegex"
    private static let caseSensitiveDefaultsKey = "filterIsCaseSensitive"
    @State private var selectedLine: Int?
    @State private var targetLine: Int?
    @State private var showFilePicker = false
    @State private var langKey: Int = 0
    @State private var isSearchFieldFocused = false
    @State private var currentSearchIndex = 0
    @State private var showMarkMenu = false
    @State private var pendingMarkText = ""
    @State private var showGoToLine = false
    @State private var goToLineInput = ""
    /// Per-window visibility of the preset filter sidebar (each window/tab is
    /// independent). The preset data itself is shared via `PresetStore.shared`.
    @State private var showSidebar = false
    @ObservedObject private var presetStore = PresetStore.shared

    var body: some View {
        Group {
            if let error = fileReader.error {
                ErrorView(message: error) {
                    showFilePicker = true
                }
            } else if fileReader.isLoading && fileReader.fileSize >= FileReader.indexProgressByteThreshold {
                LoadingView(
                    fileName: fileReader.fileName,
                    progress: fileReader.indexProgress,
                    fileSize: fileReader.fileSize
                )
            } else if fileReader.totalLines == 0 && !fileReader.isLoading {
                EmptyFileView {
                    showFilePicker = true
                }
            } else {
                mainContent
            }
        }
        .id("lang-\(langKey)")
        .background(WindowAccessor { window in
            if windowHolder.window !== window {
                windowHolder.window = window
                applyWindowTitle()
            }
        })
        .onAppear {
            wireMarkCoordinator()
            attemptExternalFileOpen()
            scheduleExternalFileOpenRetry()
        }
        .onReceive(NotificationCenter.default.publisher(for: ExternalFileOpener.notification)) { _ in
            attemptExternalFileOpen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // Re-point the shared mark coordinator at this window's engine
            // whenever it becomes key, so Cmd+M / Cmd+Shift+M and the
            // right-click mark menu always act on the focused window.
            guard let win = note.object as? NSWindow, win === windowHolder.window else { return }
            wireMarkCoordinator()
            attemptExternalFileOpen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didActivateApplicationNotification)) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == Bundle.main.bundleIdentifier {
                applyWindowTitle()
            }
        }
        .onReceive(fileReader.$fileName) { newFileName in
            let title = newFileName.isEmpty ? "Logpad" : newFileName
            windowHolder.window?.title = title
        }
        .onChange(of: splitMode) { _, newMode in
            // Any split mode change may reset the window title to the app default.
            // Re-apply the correct filename.
            DispatchQueue.main.async {
                applyWindowTitle()
            }
        }
        .onChange(of: filterCondition) { _, _ in
            // No-op: filter changes don't affect window title directly.
            // The title is preserved via autoOpenSplitIfNeeded if needed.
        }
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
            _ = item.loadObject(ofClass: URL.self) { url, _ in
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
            guard windowHolder.isKey else { return }
            showFilePicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusSearchField"))) { _ in
            guard windowHolder.isKey else { return }
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GoToLine"))) { _ in
            guard windowHolder.isKey, fileReader.totalLines > 0, !fileReader.isLoading else { return }
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
            guard windowHolder.isKey else { return }
            jumpToPreviousResult()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowMarkMenu"))) { notification in
            guard windowHolder.isKey else { return }
            if let text = notification.object as? String, !text.isEmpty {
                pendingMarkText = text
                showMarkMenu = true
            }
        }
    }

    /// Sets this window's title to the current file name (or the app name when
    /// no file is open). Scoped to this window so multiple windows/tabs each
    /// show their own file.
    private func applyWindowTitle() {
        let title = fileReader.fileName.isEmpty ? "Logpad" : fileReader.fileName
        windowHolder.window?.title = title
    }

    /// Points the shared `MarkCoordinator` callbacks at this window's engine.
    private func wireMarkCoordinator() {
        MarkCoordinator.shared.activeMarkColors = { searchEngine.activeMarkColors }
        MarkCoordinator.shared.removeMarkColor = { searchEngine.removeMarks(color: $0) }
        MarkCoordinator.shared.removeMarkText = { searchEngine.removeMarks(text: $0) }
        MarkCoordinator.shared.clearAllMarks = { searchEngine.clearMarks() }
    }

    private func attemptExternalFileOpen() {
        guard let url = ExternalFileOpener.shared.takePending(
            for: windowHolder.window,
            isKey: windowHolder.isKey,
            hasOpenFile: !fileReader.fileName.isEmpty
        ) else { return }
        _ = url.startAccessingSecurityScopedResource()
        fileReader.open(url: url)
    }

    /// Cold launch or tab creation may deliver the URL before this view is key.
    private func scheduleExternalFileOpenRetry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            attemptExternalFileOpen()
        }
    }

    private func performSearch() {
        searchEngine.search(condition: filterCondition, encoding: fileReader.encoding, lineStream: fileReader.forEachLineBytes) { [self] in
            currentSearchIndex = 0
            if let first = searchEngine.results.first {
                targetLine = first.line.id
                searchEngine.focusMatch(at: 0)
            }
            autoOpenSplitIfNeeded()
        }
    }

    /// A search with a non-empty keyword implies the user wants to see the
    /// results panel, so when the layout is still single-window, switch to
    /// up/down split by default. The user's manual split choice is preserved.
    private func autoOpenSplitIfNeeded() {
        if splitMode == .none, !filterCondition.keyword.isEmpty {
            splitMode = .horizontal
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
        searchEngine.focusMatch(at: currentSearchIndex)
    }

    private func jumpToPreviousResult() {
        guard !searchEngine.results.isEmpty else { return }
        currentSearchIndex = currentSearchIndex > 0 ? currentSearchIndex - 1 : searchEngine.results.count - 1
        targetLine = searchEngine.results[currentSearchIndex].line.id
        searchEngine.focusMatch(at: currentSearchIndex)
    }

    private func addHighlightMark(text: String, color: HighlightColor) {
        searchEngine.addMark(HighlightMark(text: text, color: color))
    }

    /// Applies preset words to the search box: joins them with `|`, appends to
    /// any existing keyword (also `|`-joined), and force-enables Regex so the
    /// alternation is honored. Mutating `filterCondition` triggers the existing
    /// `onChange` handler, which runs the search and auto-opens the split.
    private func applyPreset(words: [String]) {
        let newWords = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !newWords.isEmpty else { return }

        // Treat the current keyword as `|`-separated tokens and only append words
        // not already present, so re-applying the same group/word doesn't pile up
        // duplicates (e.g. `a|b` clicked twice stays `a|b`).
        var tokens = filterCondition.keyword
            .split(separator: "|", omittingEmptySubsequences: true)
            .map(String.init)
        for word in newWords where !tokens.contains(word) {
            tokens.append(word)
        }

        filterCondition.isRegex = true
        filterCondition.keyword = tokens.joined(separator: "|")
    }

    /// Clicking a row in the (deduplicated) result list focuses that line's
    /// first match occurrence, so subsequent Enter/arrow navigation continues
    /// from there through any further matches on the line.
    private func selectResultLine(_ displayIndex: Int) {
        guard displayIndex >= 0, displayIndex < searchEngine.lineFirstResultIndex.count else { return }
        let resultIndex = searchEngine.lineFirstResultIndex[displayIndex]
        guard resultIndex >= 0, resultIndex < searchEngine.results.count else { return }
        currentSearchIndex = resultIndex
        targetLine = searchEngine.results[resultIndex].line.id
        searchEngine.focusMatch(at: resultIndex)
    }

    /// The log area to the right of the preset sidebar: the single-window log
    /// view, or the up/down / left-right split with the filter result panel.
    @ViewBuilder
    private var logArea: some View {
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
                    results: searchEngine.lineResults,
                    matchCount: searchEngine.results.count,
                    searchRanges: { searchEngine.searchRanges(forLineID: $0) },
                    onResultSelected: { displayIndex in
                        selectResultLine(displayIndex)
                    },
                    fileName: fileReader.filePathString
                )
            }
        } else {
            VSplitView {
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
                    results: searchEngine.lineResults,
                    matchCount: searchEngine.results.count,
                    searchRanges: { searchEngine.searchRanges(forLineID: $0) },
                    onResultSelected: { displayIndex in
                        selectResultLine(displayIndex)
                    },
                    fileName: fileReader.filePathString
                )
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            ToolbarView(
                splitMode: $splitMode,
                showSidebar: $showSidebar,
                filterCondition: $filterCondition,
                isSearching: searchEngine.isSearching,
                hasResults: !searchEngine.results.isEmpty,
                onOpenFile: { showFilePicker = true },
                onSearchSubmit: { submitOrNext() },
                onPreviousResult: { jumpToPreviousResult() },
                onNextResult: { jumpToNextResult() },
                langKey: $langKey,
                isSearchFieldFocused: $isSearchFieldFocused,
                encoding: fileReader.encoding
            )

            Divider()

            if fileReader.fileChangedExternally {
                FileChangedBanner(
                    onReload: { fileReader.reload() },
                    onDismiss: { fileReader.fileChangedExternally = false }
                )
                Divider()
            }

            if showSidebar {
                HSplitView {
                    PresetSidebarView(
                        store: presetStore,
                        onApplyGroup: { applyPreset(words: $0.words.map(\.text)) },
                        onApplyWord: { applyPreset(words: [$0]) }
                    )
                    logArea
                }
            } else {
                logArea
            }
        }
        .onChange(of: filterCondition) { _, newCondition in
            UserDefaults.standard.set(newCondition.isRegex, forKey: MainView.regexDefaultsKey)
            UserDefaults.standard.set(newCondition.isCaseSensitive, forKey: MainView.caseSensitiveDefaultsKey)
            searchEngine.search(condition: newCondition, encoding: fileReader.encoding, lineStream: fileReader.forEachLineBytes) {
                applyWindowTitle()
                currentSearchIndex = 0
                if !searchEngine.results.isEmpty {
                    searchEngine.focusMatch(at: 0)
                }
                autoOpenSplitIfNeeded()
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

    var body: some View {
        VirtualLogView(
            fileReader: fileReader,
            searchEngine: searchEngine,
            targetLine: $targetLine,
            onTextSelected: onTextSelected
        )
        .background(Color(nsColor: .textBackgroundColor))
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
    @Binding var showSidebar: Bool
    @Binding var filterCondition: FilterCondition
    let isSearching: Bool
    let hasResults: Bool
    let onOpenFile: () -> Void
    let onSearchSubmit: () -> Void
    let onPreviousResult: () -> Void
    let onNextResult: () -> Void
    @Binding var langKey: Int
    @Binding var isSearchFieldFocused: Bool
    let encoding: String.Encoding

    var body: some View {
        HStack {
            Button {
                showSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.borderless)
            .foregroundColor(showSidebar ? .accentColor : .secondary)
            .help(i18n.str("sidebarToggleHint"))

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

            HStack(spacing: 2) {
                // Native NSButton tooltips keep working after the log NSTextView
                // takes first responder, unlike SwiftUI's `.help`.
                NavArrowButton(
                    systemImage: "chevron.up",
                    toolTip: i18n.str("prevMatchHint"),
                    action: onPreviousResult
                )
                .frame(width: 22, height: 20)
                .opacity(hasResults ? 1 : 0.4)

                NavArrowButton(
                    systemImage: "chevron.down",
                    toolTip: i18n.str("nextMatchHint"),
                    action: onNextResult
                )
                .frame(width: 22, height: 20)
                .opacity(hasResults ? 1 : 0.4)
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
                    splitMode = .horizontal
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                }
                .buttonStyle(.borderless)
                .foregroundColor(splitMode == .horizontal ? .accentColor : .secondary)

                Button {
                    splitMode = .vertical
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .buttonStyle(.borderless)
                .foregroundColor(splitMode == .vertical ? .accentColor : .secondary)
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

            Divider().frame(height: 20)

            // Detected text encoding (e.g. "UTF-8", "GB18030"). Surfaced so
            // the user can confirm auto-detection on non-UTF-8 files; the
            // tooltip explains the value when the field is too small to read.
            Text(TextEncodingDetector.displayName(for: encoding))
                .font(.caption)
                .foregroundColor(.secondary)
                .help(i18n.str("encodingHint"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

/// A borderless AppKit button whose tooltip is set natively, so it stays
/// reliable regardless of which view currently holds first responder.
struct NavArrowButton: NSViewRepresentable {
    let systemImage: String
    let toolTip: String
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(config)
        button.toolTip = toolTip
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.toolTip = toolTip
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}

struct FilterResultView: View {
    let results: [FilterResult]
    /// Total number of match occurrences (counts every hit, including several
    /// on the same line), shown in the header. The list itself is deduplicated
    /// to one row per line.
    let matchCount: Int
    /// Match ranges for a given 1-based line id, used to highlight the matched
    /// fragments in the preview just like the main view.
    let searchRanges: (Int) -> [NSRange]
    let onResultSelected: (Int) -> Void
    /// The file path of the currently opened log file.
    let fileName: String

    /// Builds the line preview with each match fragment given a yellow
    /// background, mirroring the main view's highlight.
    private func highlighted(_ content: String, lineID: Int) -> AttributedString {
        var attributed = AttributedString(content)
        for range in searchRanges(lineID) {
            guard range.location >= 0, range.location + range.length <= (content as NSString).length,
                  let swiftRange = Range(range, in: content) else { continue }
            let lowerOffset = content.distance(from: content.startIndex, to: swiftRange.lowerBound)
            let upperOffset = content.distance(from: content.startIndex, to: swiftRange.upperBound)
            let lower = attributed.index(attributed.startIndex, offsetByCharacters: lowerOffset)
            let upper = attributed.index(attributed.startIndex, offsetByCharacters: upperOffset)
            attributed[lower..<upper].backgroundColor = Color(nsColor: .systemYellow)
        }
        return attributed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(fileName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(i18n.str("FilterResults")): \(matchCount)")
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
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            Button {
                                onResultSelected(index)
                            } label: {
                                HStack(alignment: .top, spacing: 0) {
                                    Text("\(result.line.id)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 50, alignment: .trailing)
                                        .padding(.trailing, 6)

                                    Text(highlighted(result.line.content, lineID: result.line.id))
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

struct FileChangedBanner: View {
    let onReload: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(i18n.str("fileChangedMessage"))
                .font(.callout)
            Spacer()
            Button(i18n.str("Reload"), action: onReload)
                .keyboardShortcut("r", modifiers: .command)
            Button(i18n.str("Dismiss"), action: onDismiss)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }
}

struct LoadingView: View {
    let fileName: String
    let progress: Double
    let fileSize: Int64

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(fileName.isEmpty ? i18n.str("indexingTitle") : fileName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 260)
            Text("\(Int(progress * 100))%  ·  \(sizeText)")
                .font(.callout)
                .foregroundColor(.secondary)
                .monospacedDigit()
            Text(i18n.str("indexingHint"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
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
                    // SwiftUI resigns the field on submit; re-assert focus on the
                    // next tick so repeated Enter keeps cycling through matches.
                    DispatchQueue.main.async { focused = true }
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