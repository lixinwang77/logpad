import Foundation
import Combine

/// Fast substring test on raw UTF-8 bytes, used as a cheap prefilter so we only
/// build a `String` for lines that actually contain the term. Case-insensitive
/// matching folds ASCII A–Z only (sufficient for log content); the matched line
/// is afterwards confirmed with a Unicode-aware `String` search.
nonisolated struct ByteNeedle {
    private let raw: [UInt8]
    private let folded: [UInt8]
    private let caseInsensitive: Bool

    init(_ text: String, caseInsensitive: Bool) {
        self.caseInsensitive = caseInsensitive
        let bytes = Array(text.utf8)
        raw = bytes
        folded = bytes.map { ($0 >= 65 && $0 <= 90) ? $0 &+ 32 : $0 }
    }

    func isContained(in haystack: UnsafeRawBufferPointer) -> Bool {
        let m = raw.count
        let n = haystack.count
        if m == 0 { return true }
        if m > n { return false }

        if !caseInsensitive {
            return raw.withUnsafeBytes { needlePtr in
                memmem(haystack.baseAddress, n, needlePtr.baseAddress, m) != nil
            }
        }

        let bytes = haystack.bindMemory(to: UInt8.self)
        let first = folded[0]
        var i = 0
        let last = n - m
        while i <= last {
            var a = bytes[i]
            if a >= 65 && a <= 90 { a &+= 32 }
            if a == first {
                var matched = true
                var j = 1
                while j < m {
                    var c = bytes[i + j]
                    if c >= 65 && c <= 90 { c &+= 32 }
                    if c != folded[j] { matched = false; break }
                    j += 1
                }
                if matched { return true }
            }
            i += 1
        }
        return false
    }
}

final class SearchEngine: ObservableObject {
    /// Every match occurrence, in file order. Used for `Enter` / arrow
    /// navigation so each occurrence (even multiple on one line) is reachable.
    @Published var results: [FilterResult] = []
    @Published var isSearching: Bool = false

    /// One entry per matching line (deduplicated), for the filter result list
    /// so a line with several matches appears only once. `lineFirstResultIndex`
    /// maps each display row to the index of that line's first occurrence in
    /// `results`, so clicking a row focuses the right match for navigation.
    @Published private(set) var lineResults: [FilterResult] = []
    private(set) var lineFirstResultIndex: [Int] = []

    /// Active text marks. Mark highlights are computed lazily per visible row
    /// (see `markRanges(in:)`) rather than precomputed across the whole file,
    /// so adding a mark never triggers a full-file scan.
    @Published private(set) var marks: [HighlightMark] = []

    /// Incremented whenever `results` or `marks` change, so views can
    /// cheaply detect that visible highlights need to be refreshed.
    @Published private(set) var revision: Int = 0

    /// Fast lookup of a line's search-match ranges keyed by 1-based line id.
    /// A line may contain several matches, so every occurrence is stored.
    private(set) var resultLineIndex: [Int: [NSRange]] = [:]

    /// The match the user has navigated to (1-based line id + its range), drawn
    /// with a deeper highlight so the active occurrence stands out. `0` / `nil`
    /// means no match is currently focused.
    @Published private(set) var currentMatchLineID: Int = 0
    private(set) var currentMatchRange: NSRange?

    private var searchTask: Task<Void, Never>?

    private static let debounceNanos: UInt64 = 250_000_000

    func searchRanges(forLineID id: Int) -> [NSRange] {
        resultLineIndex[id] ?? []
    }

    /// Marks the result at `index` as the focused match and triggers a highlight
    /// refresh so the renderer can draw it with the deeper color.
    func focusMatch(at index: Int) {
        if index >= 0, index < results.count {
            let r = results[index]
            currentMatchLineID = r.line.id
            currentMatchRange = r.highlightRange.map { NSRange($0, in: r.line.content) }
        } else {
            currentMatchLineID = 0
            currentMatchRange = nil
        }
        revision &+= 1
    }

    func search(condition: FilterCondition,
                encoding: String.Encoding = .utf8,
                lineStream: @escaping (() -> Bool, (Int, UnsafeRawBufferPointer) -> Void) -> Void,
                onComplete: (() -> Void)? = nil) {
        searchTask?.cancel()

        let keyword = condition.keyword
        guard !keyword.isEmpty else {
            results = []
            lineResults = []
            lineFirstResultIndex = []
            resultLineIndex = [:]
            currentMatchLineID = 0
            currentMatchRange = nil
            isSearching = false
            revision &+= 1
            onComplete?()
            return
        }

        isSearching = true
        let isRegex = condition.isRegex
        let caseSensitive = condition.isCaseSensitive

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            // Debounce: rapid successive calls cancel the previous task before
            // it gets past this sleep, so we only scan once typing settles.
            try? await Task.sleep(nanoseconds: SearchEngine.debounceNanos)
            if Task.isCancelled { return }

            let regex: NSRegularExpression? = isRegex
                ? try? NSRegularExpression(pattern: keyword,
                                           options: caseSensitive ? [] : [.caseInsensitive])
                : nil

            // Invalid regex: report no matches instead of falling back to literal.
            if isRegex && regex == nil {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.results = []
                    self.lineResults = []
                    self.lineFirstResultIndex = []
                    self.resultLineIndex = [:]
                    self.currentMatchLineID = 0
                    self.currentMatchRange = nil
                    self.isSearching = false
                    self.revision &+= 1
                    onComplete?()
                }
                return
            }

            var found: [FilterResult] = []
            var lineFound: [FilterResult] = []
            var lineFirstIndex: [Int] = []
            var index: [Int: [NSRange]] = [:]
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            let needle = ByteNeedle(keyword, caseInsensitive: !caseSensitive)
            // The byte prefilter is only valid when the keyword and the line
            // share an encoding. UTF-8 always qualifies. For other encodings
            // the keyword is also valid as a prefilter when it is pure ASCII
            // (ASCII is byte-invariant across UTF-8/GBK/Big5/Latin-1); for
            // non-ASCII keywords we have to decode every line instead.
            let needleIsAscii = keyword.unicodeScalars.allSatisfy { $0.isASCII }
            let canPrefilter = encoding == .utf8 || needleIsAscii
            // For non-UTF-8 files, decode using the detected encoding; fall
            // back to a lenient UTF-8 substitution if a line disagrees with
            // the head sample (so a single off-encoding line doesn't drop).
            let decodeLine: (UnsafeRawBufferPointer) -> String = { bytes in
                if encoding == .utf8 {
                    return String(decoding: bytes, as: UTF8.self)
                }
                return String(data: Data(bytes), encoding: encoding)
                    ?? String(decoding: bytes, as: UTF8.self)
            }

            lineStream({ Task.isCancelled }) { lineNumber, bytes in
                if let rx = regex {
                    // Regex requires a String; build it per line. Collect every
                    // match so multiple hits on one line are all navigable.
                    let line = decodeLine(bytes)
                    let full = NSRange(line.startIndex..., in: line)
                    let id = lineNumber + 1
                    var ranges: [NSRange] = []
                    let firstResultIdx = found.count
                    for match in rx.matches(in: line, range: full) where match.range.length > 0 {
                        guard let r = Range(match.range, in: line) else { continue }
                        found.append(FilterResult(line: LogLine(id: id, content: line), highlightRange: r))
                        ranges.append(match.range)
                    }
                    if !ranges.isEmpty {
                        index[id] = ranges
                        lineFound.append(found[firstResultIdx])
                        lineFirstIndex.append(firstResultIdx)
                    }
                    return
                }

                // Literal path: cheap byte prefilter (when valid for the file's
                // encoding), decode only on a hit, then walk the line to capture
                // every occurrence of the keyword.
                if canPrefilter, !needle.isContained(in: bytes) { return }
                let line = decodeLine(bytes)
                let id = lineNumber + 1
                var ranges: [NSRange] = []
                let firstResultIdx = found.count
                var searchStart = line.startIndex
                while let r = line.range(of: keyword, options: options, range: searchStart..<line.endIndex) {
                    found.append(FilterResult(line: LogLine(id: id, content: line), highlightRange: r))
                    ranges.append(NSRange(r, in: line))
                    searchStart = r.upperBound
                }
                if !ranges.isEmpty {
                    index[id] = ranges
                    lineFound.append(found[firstResultIdx])
                    lineFirstIndex.append(firstResultIdx)
                }
            }

            if Task.isCancelled { return }

            let finalResults = found
            let finalLineResults = lineFound
            let finalLineFirstIndex = lineFirstIndex
            let finalIndex = index
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.results = finalResults
                self.lineResults = finalLineResults
                self.lineFirstResultIndex = finalLineFirstIndex
                self.resultLineIndex = finalIndex
                self.currentMatchLineID = 0
                self.currentMatchRange = nil
                self.isSearching = false
                self.revision &+= 1
                onComplete?()
            }
        }
    }

    /// Adds a text mark. Highlights are rendered lazily as rows scroll into
    /// view, so this is O(1) regardless of file size — no full-file scan.
    func addMark(_ mark: HighlightMark) {
        guard !mark.text.isEmpty else { return }
        marks.append(mark)
        revision &+= 1
    }

    /// Colors currently in use by at least one mark, in the canonical color
    /// order, for building the "remove mark" menu.
    var activeMarkColors: [HighlightColor] {
        HighlightColor.allCases.filter { color in marks.contains { $0.color == color } }
    }

    /// Removes every mark of the given color.
    func removeMarks(color: HighlightColor) {
        let remaining = marks.filter { $0.color != color }
        guard remaining.count != marks.count else { return }
        marks = remaining
        revision &+= 1
    }

    /// Removes marks whose text matches `text` (case-insensitive, mirroring how
    /// marks are matched), used by the "unmark selection" shortcut.
    func removeMarks(text: String) {
        let remaining = marks.filter { $0.text.caseInsensitiveCompare(text) != .orderedSame }
        guard remaining.count != marks.count else { return }
        marks = remaining
        revision &+= 1
    }

    /// Computes the mark highlight ranges for a single line's content. Called
    /// per visible row during rendering, so the cost scales with the viewport
    /// (a few dozen rows) rather than the whole file.
    func markRanges(in content: String) -> [(NSRange, HighlightColor)] {
        guard !marks.isEmpty, !content.isEmpty else { return [] }
        var result: [(NSRange, HighlightColor)] = []
        for mark in marks where !mark.text.isEmpty {
            var searchStart = content.startIndex
            while let range = content.range(of: mark.text,
                                            options: [.caseInsensitive],
                                            range: searchStart..<content.endIndex) {
                result.append((NSRange(range, in: content), mark.color))
                searchStart = range.upperBound
            }
        }
        return result
    }

    func clear() {
        searchTask?.cancel()
        results = []
        resultLineIndex = [:]
        currentMatchLineID = 0
        currentMatchRange = nil
        revision &+= 1
    }

    func clearMarks() {
        guard !marks.isEmpty else { return }
        marks = []
        revision &+= 1
    }
}
