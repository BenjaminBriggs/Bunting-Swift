import CryptoKit
import Foundation

/// Implements deterministic bucketing algorithm for tests and rollouts
struct Bucketing {
    /// Computes a deterministic bucket (1-100) for a given salt and local ID
    /// Algorithm:
    /// 1. Concatenate salt + ":" + localID.uuidString
    /// 2. SHA-256 hash the UTF-8 bytes
    /// 3. Take first 8 bytes as unsigned big-endian 64-bit integer
    /// 4. Return (value % 100) + 1
    ///
    /// - Parameters:
    ///   - salt: Unique salt for the test/rollout
    ///   - localID: Persistent device/user identifier
    /// - Returns: Bucket number from 1 to 100 inclusive
    static func bucket(salt: String, localID: UUID) -> Int {
        let input = "\(salt):\(localID.uuidString)"
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)

        // Take first 8 bytes and convert to UInt64 (big-endian)
        let prefix = digest.prefix(8)
        var value: UInt64 = 0
        for byte in prefix {
            value = (value << 8) | UInt64(byte)
        }

        // Compute bucket: (value % 100) + 1
        let bucket = Int((value % 100) + 1)
        return bucket
    }
}
