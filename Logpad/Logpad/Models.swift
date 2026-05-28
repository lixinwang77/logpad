import Foundation

struct LogLine: Identifiable, Equatable {
    let id: Int
    let content: String
}

struct FilterResult: Identifiable, Equatable {
    let id: UUID
    let line: LogLine
    let highlightRange: Range<String.Index>?

    init(line: LogLine, highlightRange: Range<String.Index>? = nil) {
        self.id = UUID()
        self.line = line
        self.highlightRange = highlightRange
    }
}

struct FilterCondition: Equatable {
    var keyword: String = ""
    var isRegex: Bool = false
    var isCaseSensitive: Bool = false
}

enum SplitMode: String, CaseIterable {
    case none
    case horizontal
    case vertical
}