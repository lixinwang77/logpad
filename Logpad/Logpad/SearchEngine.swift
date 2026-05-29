import Foundation
import Combine

final class SearchEngine: ObservableObject {
    @Published var results: [FilterResult] = []
    @Published var isSearching: Bool = false
    @Published var markResults: [Int: [(Range<String.Index>, HighlightColor)]] = [:]

    private var allLines: [LogLine] = []
    private var searchTask: Task<Void, Never>?

    func indexLines(_ lines: [LogLine]) {
        allLines = lines
    }

    func search(condition: FilterCondition, totalLines: Int, lineReader: @escaping (Int) -> String?, onComplete: (() -> Void)? = nil) {
        searchTask?.cancel()
        guard !condition.keyword.isEmpty else {
            results = []
            return
        }

        isSearching = true
        results = []

        searchTask = Task { @MainActor in
            var found: [FilterResult] = []

            let regex: NSRegularExpression? = condition.isRegex ? try? NSRegularExpression(
                pattern: condition.keyword,
                options: condition.isCaseSensitive ? [] : [.caseInsensitive]
            ) : nil

            for lineNumber in 0..<totalLines {
                if Task.isCancelled { break }

                let content = lineReader(lineNumber)
                guard let lineContent = content else { continue }

                var range: Range<String.Index>?

                if let rx = regex {
                    if let match = rx.firstMatch(in: lineContent, range: NSRange(lineContent.startIndex..., in: lineContent)) {
                        range = Range(match.range, in: lineContent)
                    }
                } else {
                    let searchContent = condition.isCaseSensitive ? lineContent : lineContent.lowercased()
                    let keyword = condition.isCaseSensitive ? condition.keyword : condition.keyword.lowercased()
                    if let rangeLower = searchContent.range(of: keyword) {
                        let startDistance = searchContent.distance(from: searchContent.startIndex, to: rangeLower.lowerBound)
                        let endDistance = searchContent.distance(from: searchContent.startIndex, to: rangeLower.upperBound)
                        let startIndex = lineContent.index(lineContent.startIndex, offsetBy: startDistance)
                        let endIndex = lineContent.index(lineContent.startIndex, offsetBy: endDistance)
                        range = startIndex..<endIndex
                    }
                }

                if range != nil {
                    let line = LogLine(id: lineNumber + 1, content: lineContent)
                    found.append(FilterResult(line: line, highlightRange: range))
                }
            }

            self.results = found
            self.isSearching = false
            onComplete?()
        }
    }

    func searchMarks(_ marks: [HighlightMark], totalLines: Int, lineReader: @escaping (Int) -> String?) {
        var newResults: [Int: [(Range<String.Index>, HighlightColor)]] = [:]

        for mark in marks {
            for lineNumber in 0..<totalLines {
                let content = lineReader(lineNumber) ?? ""
                let searchContent = content.lowercased()
                let keyword = mark.text.lowercased()

                var searchStart = searchContent.startIndex
                while let range = searchContent.range(of: keyword, range: searchStart..<searchContent.endIndex) {
                    let startDistance = searchContent.distance(from: searchContent.startIndex, to: range.lowerBound)
                    let endDistance = searchContent.distance(from: searchContent.startIndex, to: range.upperBound)
                    let startIndex = content.index(content.startIndex, offsetBy: startDistance)
                    let endIndex = content.index(content.startIndex, offsetBy: endDistance)
                    let highlightRange = startIndex..<endIndex

                    if newResults[lineNumber] == nil {
                        newResults[lineNumber] = []
                    }
                    newResults[lineNumber]?.append((highlightRange, mark.color))

                    searchStart = range.upperBound
                }
            }
        }

        self.markResults = newResults
        self.objectWillChange.send()
    }

    func clear() {
        results = []
        searchTask?.cancel()
    }

    func clearMarks() {
        markResults = [:]
    }
}