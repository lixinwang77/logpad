import Foundation
import Combine

final class FileReader: ObservableObject {
    private var fileHandle: FileHandle?
    private var filePath: URL?
    private var lineOffsets: [UInt64] = [0]
    private(set) var totalLines: Int = 0

    @Published var isLoading: Bool = false
    @Published var error: String?

    var fileName: String {
        filePath?.lastPathComponent ?? ""
    }

    func open(url: URL) {
        close()
        filePath = url
        lineOffsets = [0]
        totalLines = 0
        error = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            error = "File does not exist"
            return
        }

        do {
            fileHandle = try FileHandle(forReadingFrom: url)
            indexFile()
        } catch {
            self.error = "Cannot open file: \(error.localizedDescription)"
        }
    }

    private func indexFile() {
        guard let handle = fileHandle else { return }
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var offsets: [UInt64] = [0]
            let chunkSize: UInt64 = 1024 * 1024
            var buffer = Data()
            var currentOffset: UInt64 = 0

            do {
                while true {
                    let data = try handle.read(upToCount: Int(chunkSize))
                    if data == nil || data!.isEmpty { break }
                    buffer.append(data!)

                    while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        let idx = buffer.distance(from: buffer.startIndex, to: newlineIndex)
                        offsets.append(currentOffset + UInt64(idx) + 1)
                        buffer.removeSubrange(0...idx)
                        currentOffset += UInt64(idx) + 1
                    }
                }

                if !buffer.isEmpty {
                    offsets.append(currentOffset + UInt64(buffer.count))
                }
            } catch {
                // read truncated
            }

            DispatchQueue.main.async {
                self.lineOffsets = offsets
                self.totalLines = offsets.count - 1
                self.isLoading = false
                NotificationCenter.default.post(name: NSNotification.Name("FileDidLoad"), object: nil)
            }
        }
    }

    func readLine(at lineNumber: Int) -> String? {
        guard let handle = fileHandle,
              lineNumber >= 0 && lineNumber < lineOffsets.count else { return nil }

        let startOffset = lineOffsets[lineNumber]
        let endOffset = lineNumber + 1 < lineOffsets.count ? lineOffsets[lineNumber + 1] : startOffset + 4096

        guard startOffset < endOffset else { return "" }

        do {
            try handle.seek(toOffset: startOffset)
            guard let data = try handle.read(upToCount: Int(endOffset - startOffset)) else { return nil }
            var line = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            if line.hasSuffix("\n") {
                line.removeLast()
            }
            return line
        } catch {
            return nil
        }
    }

    func readLines(from: Int, count: Int) -> [LogLine] {
        guard from >= 0 else { return [] }
        var lines: [LogLine] = []
        for i in from..<min(from + count, lineOffsets.count) {
            if let content = readLine(at: i) {
                lines.append(LogLine(id: i + 1, content: content))
            }
        }
        return lines
    }

    func close() {
        try? fileHandle?.close()
        fileHandle = nil
        filePath = nil
    }

    deinit {
        close()
    }
}