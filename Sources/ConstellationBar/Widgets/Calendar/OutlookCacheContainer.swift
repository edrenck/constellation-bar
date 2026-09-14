import Foundation

/// Bounded codec for Outlook's local Nostromo-i cache. Live blocks must be
/// selected through the checksummed directory by OutlookCacheReader.
struct OutlookCacheContainer {
    static let maximumFileBytes = 256 * 1024 * 1024
    static let maximumBlockBytes = 16 * 1024 * 1024

    static func crc(_ bytes: Data.SubSequence) -> UInt32 {
        var value: UInt32 = 0xffffffff
        for byte in bytes {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = (value >> 1) ^ (value & 1 != 0 ? 0xedb88320 : 0) }
        }
        return value ^ 0xffffffff
    }

    static func inflate(_ input: [UInt8], size: Int) -> Data? {
        guard size > 0, size <= maximumBlockBytes else { return nil }
        var output: [UInt8] = []
        output.reserveCapacity(size)
        var cursor = 0
        func extendedLength(_ initial: Int) -> Int? {
            var length = initial
            while true {
                guard cursor < input.count else { return nil }
                let byte = Int(input[cursor]); cursor += 1
                length += byte
                if byte != 255 { return length }
            }
        }
        while cursor < input.count {
            let token = Int(input[cursor]); cursor += 1
            var literals = token >> 4
            if literals == 15 {
                guard let length = extendedLength(literals) else { return nil }
                literals = length
            }
            guard cursor + literals <= input.count, output.count + literals <= size else { return nil }
            output += input[cursor..<(cursor + literals)]; cursor += literals
            if cursor == input.count { break }
            guard cursor + 2 <= input.count else { return nil }
            let distance = Int(input[cursor]) | (Int(input[cursor + 1]) << 8); cursor += 2
            guard distance > 0, distance <= output.count else { return nil }
            var length = (token & 15) + 4
            if token & 15 == 15 {
                guard let expanded = extendedLength(length) else { return nil }
                length = expanded
            }
            guard output.count + length <= size else { return nil }
            for _ in 0..<length { output.append(output[output.count - distance]) }
        }
        return output.count == size ? Data(output) : nil
    }
}
