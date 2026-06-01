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

    /// Watches the open file for external writes / deletion / replacement.
    private var watchSource: DispatchSourceFileSystemObject?
    /// Coalesces bursts of file-system events (e.g. an actively appended log)
    /// into a single change notification.
    private var changeDebounce: DispatchWorkItem?

    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published private(set) var fileName: String = ""
    /// Detected text encoding of the open file (UTF-8, GB18030, Big5, …).
    /// Determined once in `open()` from a 64 KB head sample and reused by both
    /// the line reader and the search engine.
    @Published private(set) var encoding: String.Encoding = .utf8
    /// Set when the file is modified on disk outside the app; the UI surfaces a
    /// reload prompt. Cleared by `reload()` or when dismissed.
    @Published var fileChangedExternally: Bool = false
    /// Bumped by `reload()` (not by opening a new file) so the renderer can tell
    /// a reload apart from a fresh open and restore the prior scroll position.
    @Published private(set) var reloadGeneration: Int = 0

    func open(url: URL) {
        close()
        filePath = url
        fileName = url.lastPathComponent
        lineOffsets = [0]
        totalLines = 0
        error = nil
        fileChangedExternally = false
        encoding = .utf8

        guard FileManager.default.fileExists(atPath: url.path) else {
            error = "File does not exist"
            return
        }

        do {
            fileHandle = try FileHandle(forReadingFrom: url)
            // Detect the encoding from a 64 KB head sample via a separate
            // handle (so the main handle's offset stays at 0). This is fast
            // and only runs once per open, so doing it on the main thread is
            // fine and lets the UI display the encoding immediately.
            encoding = TextEncodingDetector.detect(url: url)
            startWatching(url: url)
            indexFile()
        } catch {
            self.error = "Cannot open file: \(error.localizedDescription)"
        }
    }

    /// Re-indexes the currently open file from disk, clearing the change flag.
    /// Bumps `reloadGeneration` first so the renderer keeps the scroll position.
    func reload() {
        guard let url = filePath else { return }
        reloadGeneration += 1
        open(url: url)
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
            // Use the file's detected encoding; if a single line is somehow
            // invalid in it (rare — only when the body diverges from the
            // head sample), fall back to ISO Latin-1 so the line still renders.
            var line = String(data: data, encoding: encoding) ?? String(data: data, encoding: .isoLatin1) ?? ""
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
        stopWatching()
        ioLock.lock()
        defer { ioLock.unlock() }
        try? fileHandle?.close()
        fileHandle = nil
        filePath = nil
        fileName = ""
    }

    // MARK: - External change detection

    /// Opens a lightweight event-only descriptor on the path and reports writes,
    /// extends, deletes and atomic-replace (rename) so the UI can offer a reload.
    private func startWatching(url: URL) {
        stopWatching()

        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.scheduleChangeNotification()
        }
        source.setCancelHandler { Darwin.close(fd) }
        watchSource = source
        source.resume()
    }

    private func stopWatching() {
        changeDebounce?.cancel()
        changeDebounce = nil
        watchSource?.cancel()
        watchSource = nil
    }

    private func scheduleChangeNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.changeDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.fileChangedExternally = true
            }
            self.changeDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    deinit {
        close()
    }
}