import Foundation
import Combine

final class VirtualScrollManager: ObservableObject {
    @Published var visibleRange: Range<Int> = 0..<0

    var lineHeight: CGFloat = 20
    var visibleLineCount: Int = 50

    func updateVisible(startLine: Int) {
        let start = max(0, startLine)
        let end = min(start + visibleLineCount + 10, start + visibleLineCount * 2)
        visibleRange = start..<end
    }
}