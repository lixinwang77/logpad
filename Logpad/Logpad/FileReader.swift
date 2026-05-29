import Foundation
import Combine

final class FileReader: ObservableObject {
    private var fileHandle: FileHandle?
    private var filePath: URL?
    private var lineOffsets: [UInt64] = [0]
    private(set) var totalLines: Int = 0

    /// Serializes access to the shared file handle so concurrent reads from the
    /// UI (rendering) and the background search task can't interleave seeks.
    private let ioLock = NSLock()

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
            offsets.reserveCapacity(1 << 20)
            let chunkSize = 4 * 1024 * 1024
            var base: UInt64 = 0

            do {
                while true {
                    guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else { break }

                    // Scan each chunk in place with memchr; a newline is a single
                    // byte so it never spans a chunk boundary, and we only record
                    // offsets (no buffer mutation) — O(n) over the file.
                    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                        guard let start = raw.baseAddress else { return }
                        var ptr = start
                        var remaining = raw.count
                        while remaining > 0, let found = memchr(ptr, 0x0A, remaining) {
                            let hit = UnsafeRawPointer(found)
                            offsets.append(base + UInt64(hit - start) + 1)
                            let consumed = (hit - ptr) + 1
                            ptr = hit + 1
                            remaining -= consumed
                        }
                    }

                    base += UInt64(data.count)
                }

                // Account for a final line that isn't terminated by a newline.
                if offsets.last != base {
                    offsets.append(base)
                }
            } catch {
                // read truncated
            }

            DispatchQueue.main.async {
                self.ioLock.lock()
                self.lineOffsets = offsets
                self.totalLines = offsets.count - 1
                self.ioLock.unlock()
                self.isLoading = false
                NotificationCenter.default.post(name: NSNotification.Name("FileDidLoad"), object: nil)
            }
        }
    }

    func readLine(at lineNumber: Int) -> String? {
        ioLock.lock()
        defer { ioLock.unlock() }

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

    /// Streams the whole file sequentially (using a dedicated file handle so it
    /// doesn't contend with per-line UI reads) and invokes `handler` with each
    /// line's 0-based index and its raw bytes (newline excluded). Callers can
    /// prefilter on bytes and only decode matching lines, which is much faster
    /// than building a String per line. The buffer passed to `handler` is only
    /// valid for the duration of that call. Stops early if `isCancelled`
    /// returns true.
    func forEachLineBytes(isCancelled: () -> Bool, _ handler: (Int, UnsafeRawBufferPointer) -> Void) {
        guard let url = filePath, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let chunkSize = 4 * 1024 * 1024
        var carry = Data()
        var lineIndex = 0

        while true {
            if isCancelled() { return }
            guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else { break }

            var buffer: Data
            if carry.isEmpty {
                buffer = data
            } else {
                buffer = carry
                buffer.append(data)
                carry = Data()
            }

            var leftover = Data()
            buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let start = raw.baseAddress else { return }
                var ptr = start
                var remaining = raw.count
                while remaining > 0, let found = memchr(ptr, 0x0A, remaining) {
                    let hit = UnsafeRawPointer(found)
                    let lineLen = hit - ptr
                    handler(lineIndex, UnsafeRawBufferPointer(start: ptr, count: lineLen))
                    lineIndex += 1
                    let consumed = lineLen + 1
                    ptr = hit + 1
                    remaining -= consumed
                }
                if remaining > 0 {
                    leftover = Data(bytes: ptr, count: remaining)
                }
            }
            carry = leftover
        }

        if isCancelled() { return }
        if !carry.isEmpty {
            carry.withUnsafeBytes { raw in
                handler(lineIndex, raw)
            }
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
        ioLock.lock()
        defer { ioLock.unlock() }
        try? fileHandle?.close()
        fileHandle = nil
        filePath = nil
    }

    deinit {
        close()
    }
}