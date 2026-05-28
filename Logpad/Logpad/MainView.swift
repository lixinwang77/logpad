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
    }

    private func performSearch() {
        searchEngine.search(condition: filterCondition, totalLines: fileReader.totalLines) { lineNumber in
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
                onSearchSubmit: { performSearch() },
                langKey: $langKey,
                isSearchFieldFocused: $isSearchFieldFocused
            )

            Divider()

            if splitMode == .none {
                LogContentView(
                    fileReader: fileReader,
                    searchResults: searchEngine.results,
                    targetLine: $targetLine
                )
            } else if splitMode == .vertical {
                HSplitView {
                    LogContentView(
                        fileReader: fileReader,
                        searchResults: searchEngine.results,
                        targetLine: $targetLine
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
                        searchResults: searchEngine.results,
                        targetLine: $targetLine
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
    }
}

struct LogContentView: View {
    @ObservedObject var fileReader: FileReader
    let searchResults: [FilterResult]
    @Binding var targetLine: Int?

    private let lineHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let total = fileReader.totalLines

                        if total > 0 {
                            ForEach(0..<total, id: \.self) { row in
                                LogLineRow(
                                    lineNumber: row + 1,
                                    content: fileReader.readLine(at: row) ?? "",
                                    isHighlighted: searchResults.contains { $0.line.id == row + 1 }
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
                            proxy.scrollTo(line, anchor: .top)
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
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("\(lineNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, 8)

            Text(content)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.vertical, 1)
        .background(isHighlighted ? Color.yellow.opacity(0.3) : Color.clear)
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
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack {
            Button(action: onOpenFile) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)

            Divider().frame(height: 20)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(i18n.str("Search..."), text: $filterCondition.keyword)
                    .textFieldStyle(.plain)
                    .frame(width: 180)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        onSearchSubmit()
                    }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .onChange(of: isSearchFieldFocused) { _, newValue in
                if newValue {
                    isTextFieldFocused = true
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