import Foundation

// MARK: - Data <-> hex

extension Data {
    init?(hexString: String) {
        let hex = hexString.lowercased()
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex

        for _ in 0..<len {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Secure Memory Zeroing

extension Data {
    /// Zero out the contents of this Data buffer using memset_s (guaranteed not to be optimized away).
    /// Note: Swift Data is a value type with copy-on-write. This zeros the primary storage location
    /// but cannot guarantee all transient copies are erased.
    mutating func zeroOut() {
        guard !isEmpty else { return }
        withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = memset_s(base, ptr.count, 0, ptr.count)
        }
    }
}
