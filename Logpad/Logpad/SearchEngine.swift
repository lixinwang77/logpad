import Foundation
import Combine

final class SearchEngine: ObservableObject {
    @Published var results: [FilterResult] = []
    @Published var isSearching: Bool = false

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

    func clear() {
        results = []
        searchTask?.cancel()
    }
}