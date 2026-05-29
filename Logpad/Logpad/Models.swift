import Foundation
import SwiftUI

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

enum HighlightColor: String, CaseIterable {
    case red = "Red"
    case orange = "Orange"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        }
    }
}

struct HighlightMark: Equatable {
    let text: String
    let color: HighlightColor
}