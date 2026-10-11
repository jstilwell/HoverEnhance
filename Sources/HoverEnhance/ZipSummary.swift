import Foundation

/// What's inside a zip file, read from the list at its end (the central directory) without
/// unpacking anything. Archives come from anywhere, so every number in one is checked before use:
/// a crafted size or offset must give nothing, not a crash.
struct ZipSummary: Sendable, Equatable {
    /// Files and folders, not counting the `__MACOSX` resource forks macOS adds to archives it makes.
    var files: Int
    var folders: Int
    /// Nil when the archive lists too much to add up quickly; `files` then counts every entry.
    var unpackedSize: Int64?
    var isEncrypted: Bool

    /// Central directories larger than this are left alone; it's roughly half a million entries.
    static let maximumDirectorySize = 32 << 20

    static func read(_ url: URL, maximumDirectorySize: Int = maximumDirectorySize) -> ZipSummary? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        func read(at offset: UInt64, count: Int) -> Data? {
            guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.read(upToCount: count),
                  data.count == count else { return nil }
            return data
        }

        guard let size = try? handle.seekToEnd(), size >= 22 else { return nil }
        // The end record is 22 bytes plus a comment of up to 64 KB; a Zip64 locator sits just before it.
        let tailLength = Int(min(size, 22 + 0xFFFF + 20))
        guard let tail = read(at: size - UInt64(tailLength), count: tailLength),
              let end = endRecord(in: tail) else { return nil }

        var entries = UInt64(end.entries), directorySize = UInt64(end.directorySize), directoryOffset = UInt64(end.directoryOffset)
        if end.entries == 0xFFFF || end.directorySize == 0xFFFF_FFFF || end.directoryOffset == 0xFFFF_FFFF {
            // Zip64: the locator just before the end record says where the larger record is.
            guard end.index >= 20, tail.uint32(at: end.index - 20) == 0x0706_4B50,
                  let recordOffset = tail.uint64(at: end.index - 20 + 8),
                  let record = read(at: recordOffset, count: 56), record.uint32(at: 0) == 0x0606_4B50,
                  let count = record.uint64(at: 32), let length = record.uint64(at: 40), let offset = record.uint64(at: 48) else { return nil }
            (entries, directorySize, directoryOffset) = (count, length, offset)
        }

        guard directorySize <= UInt64(maximumDirectorySize) else {
            return ZipSummary(files: Int(clamping: entries), folders: 0, unpackedSize: nil, isEncrypted: false)
        }
        // Written as a subtraction so a crafted offset near the top of the range can't overflow.
        guard directorySize <= size, directoryOffset <= size - directorySize,
              let directory = read(at: directoryOffset, count: Int(directorySize)) else { return nil }
        return summarize(directory: directory, entries: entries)
    }

    /// The end of central directory record, found by its signature from the end backwards.
    private static func endRecord(in tail: Data) -> (index: Int, entries: UInt16, directorySize: UInt32, directoryOffset: UInt32)? {
        var index = tail.count - 22
        while index >= 0 {
            if tail.uint32(at: index) == 0x0605_4B50,
               let entries = tail.uint16(at: index + 10), let size = tail.uint32(at: index + 12), let offset = tail.uint32(at: index + 16) {
                return (index, entries, size, offset)
            }
            index -= 1
        }
        return nil
    }

    private static func summarize(directory: Data, entries: UInt64) -> ZipSummary? {
        var summary = ZipSummary(files: 0, folders: 0, unpackedSize: 0, isEncrypted: false)
        var position = 0
        for _ in 0..<entries {
            guard directory.uint32(at: position) == 0x0201_4B50,
                  let flags = directory.uint16(at: position + 8),
                  var unpacked = directory.uint32(at: position + 24).map(UInt64.init),
                  let nameLength = directory.uint16(at: position + 28).map(Int.init),
                  let extraLength = directory.uint16(at: position + 30).map(Int.init),
                  let commentLength = directory.uint16(at: position + 32).map(Int.init),
                  position + 46 + nameLength + extraLength <= directory.count else { return nil }
            let name = String(decoding: directory.dropFirst(position + 46).prefix(nameLength), as: UTF8.self)
            if unpacked == 0xFFFF_FFFF {
                // The real size is in the Zip64 extra field, whose first value it is.
                unpacked = zip64Size(in: directory, from: position + 46 + nameLength, length: extraLength) ?? unpacked
            }
            position += 46 + nameLength + extraLength + commentLength

            if name.hasPrefix("__MACOSX/") { continue }
            if flags & 1 != 0 { summary.isEncrypted = true }
            if name.hasSuffix("/") {
                summary.folders += 1
            } else {
                summary.files += 1
                // Claimed sizes can be anything; the total stops at the largest number rather than overflowing.
                let (total, overflowed) = (summary.unpackedSize ?? 0).addingReportingOverflow(Int64(clamping: unpacked))
                summary.unpackedSize = overflowed ? .max : total
            }
        }
        return summary
    }

    private static func zip64Size(in data: Data, from start: Int, length: Int) -> UInt64? {
        var position = start
        while position + 4 <= start + length {
            guard let id = data.uint16(at: position), let size = data.uint16(at: position + 2).map(Int.init) else { return nil }
            if id == 0x0001 { return data.uint64(at: position + 4) }
            position += 4 + size
        }
        return nil
    }

    /// "12 files in 3 folders · 48 MB unpacked · Encrypted".
    var label: String {
        func count(_ number: Int, _ noun: String) -> String { "\(number) \(noun)\(number == 1 ? "" : "s")" }
        var parts = [unpackedSize == nil ? count(files, "item") : folders > 0 ? "\(count(files, "file")) in \(count(folders, "folder"))" : count(files, "file")]
        if let unpackedSize { parts.append(ByteCountFormatter.string(fromByteCount: unpackedSize, countStyle: .file) + " unpacked") }
        if isEncrypted { parts.append("Encrypted") }
        return parts.joined(separator: " · ")
    }
}

/// Little-endian reads that come back nil past the end, for parsing file formats.
extension Data {
    func uint16(at offset: Int) -> UInt16? { integer(at: offset) }
    func uint32(at offset: Int) -> UInt32? { integer(at: offset) }
    func uint64(at offset: Int) -> UInt64? { integer(at: offset) }

    private func integer<Value: FixedWidthInteger>(at offset: Int) -> Value? {
        let size = MemoryLayout<Value>.size
        guard offset >= 0, offset + size <= count else { return nil }
        return withUnsafeBytes { Value(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: Value.self)) }
    }
}
