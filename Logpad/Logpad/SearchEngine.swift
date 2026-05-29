import Foundation
import Combine

/// Fast substring test on raw UTF-8 bytes, used as a cheap prefilter so we only
/// build a `String` for lines that actually contain the term. Case-insensitive
/// matching folds ASCII A–Z only (sufficient for log content); the matched line
/// is afterwards confirmed with a Unicode-aware `String` search.
struct ByteNeedle {
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
    @Published var results: [FilterResult] = []
    @Published var isSearching: Bool = false
    @Published var markResults: [Int: [(NSRange, HighlightColor)]] = [:]

    /// Incremented whenever `results` or `markResults` change, so views can
    /// cheaply detect that visible highlights need to be refreshed.
    @Published private(set) var revision: Int = 0

    /// Fast lookup of a line's search-match range keyed by 1-based line id.
    private(set) var resultLineIndex: [Int: NSRange] = [:]

    private var searchTask: Task<Void, Never>?
    private var markTask: Task<Void, Never>?

    private static let debounceNanos: UInt64 = 250_000_000

    func searchRange(forLineID id: Int) -> NSRange? {
        resultLineIndex[id]
    }

    func search(condition: FilterCondition,
                lineStream: @escaping (() -> Bool, (Int, UnsafeRawBufferPointer) -> Void) -> Void,
                onComplete: (() -> Void)? = nil) {
        searchTask?.cancel()

        let keyword = condition.keyword
        guard !keyword.isEmpty else {
            results = []
            resultLineIndex = [:]
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
                    self.resultLineIndex = [:]
                    self.isSearching = false
                    self.revision &+= 1
                    onComplete?()
                }
                return
            }

            var found: [FilterResult] = []
            var index: [Int: NSRange] = [:]
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            let needle = ByteNeedle(keyword, caseInsensitive: !caseSensitive)

            lineStream({ Task.isCancelled }) { lineNumber, bytes in
                if let rx = regex {
                    // Regex requires a String; build it per line.
                    let line = String(decoding: bytes, as: UTF8.self)
                    let full = NSRange(line.startIndex..., in: line)
                    if let match = rx.firstMatch(in: line, range: full),
                       let r = Range(match.range, in: line) {
                        let id = lineNumber + 1
                        found.append(FilterResult(line: LogLine(id: id, content: line), highlightRange: r))
                        index[id] = NSRange(r, in: line)
                    }
                    return
                }

                // Literal path: cheap byte prefilter, decode only on a hit.
                guard needle.isContained(in: bytes) else { return }
                let line = String(decoding: bytes, as: UTF8.self)
                guard let r = line.range(of: keyword, options: options) else { return }
                let id = lineNumber + 1
                found.append(FilterResult(line: LogLine(id: id, content: line), highlightRange: r))
                index[id] = NSRange(r, in: line)
            }

            if Task.isCancelled { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.results = found
                self.resultLineIndex = index
                self.isSearching = false
                self.revision &+= 1
                onComplete?()
            }
        }
    }

    func searchMarks(_ marks: [HighlightMark],
                     lineStream: @escaping (() -> Bool, (Int, UnsafeRawBufferPointer) -> Void) -> Void) {
        markTask?.cancel()
        let activeMarks = marks.filter { !$0.text.isEmpty }

        guard !activeMarks.isEmpty else {
            markResults = [:]
            revision &+= 1
            return
        }

        markTask = Task.detached(priority: .userInitiated) { [weak self] in
            var newResults: [Int: [(NSRange, HighlightColor)]] = [:]
            let prepared = activeMarks.map {
                (needle: ByteNeedle($0.text, caseInsensitive: true), text: $0.text, color: $0.color)
            }

            // Single sequential pass; byte-prefilter, decode only on a hit.
            lineStream({ Task.isCancelled }) { lineNumber, bytes in
                guard prepared.contains(where: { $0.needle.isContained(in: bytes) }) else { return }
                let line = String(decoding: bytes, as: UTF8.self)

                for item in prepared {
                    var searchStart = line.startIndex
                    while let range = line.range(of: item.text,
                                                 options: [.caseInsensitive],
                                                 range: searchStart..<line.endIndex) {
                        newResults[lineNumber, default: []].append((NSRange(range, in: line), item.color))
                        searchStart = range.upperBound
                    }
                }
            }

            if Task.isCancelled { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.markResults = newResults
                self.revision &+= 1
            }
        }
    }

    func clear() {
        searchTask?.cancel()
        results = []
        resultLineIndex = [:]
        revision &+= 1
    }

    func clearMarks() {
        markTask?.cancel()
        markResults = [:]
        revision &+= 1
    }
}
