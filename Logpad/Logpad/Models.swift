import Foundation
import SwiftUI

nonisolated struct LogLine: Identifiable, Equatable {
    let id: Int
    let content: String
}

nonisolated struct FilterResult: Identifiable, Equatable {
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

    /// Localization key for the human-readable color name (e.g. `colorRed`).
    var localizedNameKey: String { "color\(rawValue)" }
}

struct HighlightMark: Equatable {
    let text: String
    let color: HighlightColor
}

/// A single plain-text filter word inside a preset group. Applying it appends
/// the text to the search box; the search options (Regex/Aa) are not stored
/// per word.
struct FilterPresetWord: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
}

/// A named group of preset filter words shown in the left sidebar. Applying the
/// whole group joins all words with `|` into a single regex.
struct FilterPresetGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String              // unique (case-insensitive); enforced in PresetStore
    var words: [FilterPresetWord]
}