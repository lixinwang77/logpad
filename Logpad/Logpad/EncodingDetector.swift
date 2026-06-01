import Foundation
import CoreFoundation

private extension String.Encoding {
    /// GB18030 (a superset of GBK). Not exposed directly on `String.Encoding`,
    /// so we bridge via `CFStringConvertEncodingToNSStringEncoding`.
    static let gb18030 = String.Encoding(rawValue:
        CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    /// Big5 (Traditional Chinese).
    static let big5 = String.Encoding(rawValue:
        CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
}

/// Detects the text encoding of a file by sampling the first ~64 KB and trying
/// a small ladder of strict decoders. UTF-8 (with or without BOM) is tried
/// first; the Chinese legacy encodings GB18030 (a superset of GBK) and Big5
/// are tried next; ISO Latin-1 is the guaranteed fallback so the reader still
/// produces *something* on binary-ish content.
///
/// `String(data:encoding:)` is strict — it returns nil on any invalid byte
/// sequence — so the first candidate that decodes the whole sample losslessly
/// is the right one. For ASCII-only samples every candidate decodes correctly
/// (ASCII is invariant), so UTF-8 wins and the result matches what the file
/// would yield under any of the other encodings.
enum TextEncodingDetector {
    private static let sampleSize = 64 * 1024

    static func detect(url: URL) -> String.Encoding {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .utf8 }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: sampleSize), !data.isEmpty else {
            return .utf8
        }
        return detect(data: data)
    }

    static func detect(data: Data) -> String.Encoding {
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return .utf8
        }
        if data.count >= 2 {
            if data[0] == 0xFE && data[1] == 0xFF { return .utf16BigEndian }
            if data[0] == 0xFF && data[1] == 0xFE { return .utf16LittleEndian }
        }

        if String(data: data, encoding: .utf8) != nil { return .utf8 }

        // GB18030's 2-byte lead/trail ranges are so wide (lead 0x81–0xFE,
        // trail 0x40–0xFE) that a strict decode "succeeds" on most other
        // Chinese legacy encodings — including Big5 — but produces gibberish
        // (lots of Hiragana / Katakana / random symbols). Disambiguate by
        // scoring each candidate's decoded text: characters in the CJK
        // Unified Ideographs block count as +1, anything else non-ASCII
        // counts as −3, so a wrong encoding is heavily penalised.
        let big5Decoded = String(data: data, encoding: .big5)
        let gb18030Decoded = String(data: data, encoding: .gb18030)

        if let s1 = big5Decoded, let s2 = gb18030Decoded {
            // GB18030 is far more common than Big5; default to it on a tie.
            return cjkScore(s1) > cjkScore(s2) ? .big5 : .gb18030
        } else if big5Decoded != nil {
            return .big5
        } else if gb18030Decoded != nil {
            return .gb18030
        } else {
            return .isoLatin1
        }
    }

    /// `cjk − bad × 3`, where `cjk` is characters in the CJK Unified
    /// Ideographs block (U+4E00–U+9FFF) and `bad` is non-ASCII characters
    /// outside it. Decoding with the wrong legacy Chinese encoding lands
    /// in Hiragana / Katakana / Latin extended / symbols, so `bad` sharply
    /// punishes mismatches.
    private static func cjkScore(_ s: String) -> Int {
        var cjk = 0
        var bad = 0
        for scalar in s.unicodeScalars {
            let cp = scalar.value
            if cp < 0x80 { continue }
            if cp >= 0x4E00 && cp <= 0x9FFF { cjk += 1 } else { bad += 1 }
        }
        return cjk - bad * 3
    }

    /// Short, user-visible label for the encoding (e.g. for the toolbar).
    static func displayName(for encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .utf16BigEndian: return "UTF-16 BE"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .gb18030: return "GB18030"
        case .big5: return "Big5"
        case .isoLatin1: return "ISO Latin-1"
        default: return "Unknown"
        }
    }
}
