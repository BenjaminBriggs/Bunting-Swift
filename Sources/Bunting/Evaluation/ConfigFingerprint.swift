import Foundation

/// Encoder for Bunting **config fingerprints**.
///
/// A fingerprint is a compact, verifiable string that captures exactly which
/// resolution path each flag took for this client on a given published config
/// version. The Bunting admin can decode it back to every flag's resolved value
/// and the reason it resolved that way.
///
/// Format: `<config_version>.<HEX>`, where the hex is a byte-aligned bitstream
/// packed MSB-first:
///
/// ```
/// fmt      4 bits   fingerprint format version (currently 1)
/// env      2 bits   0 = development, 1 = beta, 2 = production
/// per-flag          ceil(log2(pathCount)) bits per flag, flags sorted by key
/// (pad to whole bytes with zero bits)
/// crc      8 bits   CRC-8 (poly 0x07, init 0x00) over the padded payload bytes
/// ```
///
/// The per-flag "paths" are the terminal resolution outcomes for a flag in an
/// environment, enumerated deterministically so encoder and decoder agree:
/// `paths[0]` is the environment default, followed by each variant in `order`
/// ascending (conditional → 1 path, test → 1 path per group, rollout → 1 path).
///
/// This must stay byte-for-byte compatible with the admin's reference codec in
/// `bunting-admin/src/lib/fingerprint.ts`. See `docs/config-fingerprint.md`.
enum ConfigFingerprint {
    /// The fingerprint format version this encoder produces.
    static let format = 1

    /// Number of bits needed to index `count` paths. A single-path flag costs 0 bits.
    ///
    /// Equivalent to `ceil(log2(count))`, computed with integer math to avoid any
    /// floating-point rounding at powers of two.
    static func bitWidth(_ count: Int) -> Int {
        guard count > 1 else { return 0 }
        var bits = 0
        var n = count - 1
        while n > 0 {
            bits += 1
            n >>= 1
        }
        return bits
    }

    /// CRC-8/SMBUS (polynomial `0x07`, init `0x00`) over `bytes`.
    static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                if crc & 0x80 != 0 {
                    crc = (crc << 1) ^ 0x07
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }

    /// MSB-first bit packer matching the admin reference `BitWriter`.
    private struct BitWriter {
        private var bits: [UInt8] = []

        mutating func write(_ value: Int, width: Int) {
            guard width > 0 else { return }
            var i = width - 1
            while i >= 0 {
                bits.append(UInt8((value >> i) & 1))
                i -= 1
            }
        }

        /// Packs the accumulated bits MSB-first into bytes, zero-padding the final byte.
        func toBytes() -> [UInt8] {
            var out: [UInt8] = []
            var i = 0
            while i < bits.count {
                var b: UInt8 = 0
                for j in 0..<8 {
                    let bit = (i + j) < bits.count ? bits[i + j] : 0
                    b = (b << 1) | bit
                }
                out.append(b)
                i += 8
            }
            return out
        }
    }

    /// Builds a fingerprint string from per-flag path selections.
    ///
    /// - Parameters:
    ///   - configVersion: The `config_version` of the artifact the selections came from.
    ///   - environmentIndex: `0` development, `1` beta, `2` production.
    ///   - flagWidthsSortedByKey: Each flag's bit width, in ascending key order.
    ///   - selections: Flag key → winning path index (defaults to `0` if absent).
    static func encode(
        configVersion: String,
        environmentIndex: Int,
        flagWidthsSortedByKey: [(key: String, width: Int)],
        selections: [String: Int]
    ) -> String {
        var writer = BitWriter()
        writer.write(format, width: 4)
        writer.write(environmentIndex, width: 2)
        for entry in flagWidthsSortedByKey {
            writer.write(selections[entry.key] ?? 0, width: entry.width)
        }
        var bytes = writer.toBytes()
        bytes.append(crc8(bytes))
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        return "\(configVersion).\(hex)"
    }

    /// Computes the fingerprint for a fully resolved client state.
    ///
    /// Evaluates every flag in `configuration` for `environment` (using the same
    /// engine as flag reads, but recording which path won rather than the value)
    /// and encodes the selections. Local developer overrides are intentionally
    /// excluded — the fingerprint describes the resolution the *artifact* produces.
    static func compute(
        configuration: BuntingConfiguration,
        environment: BuntingEnvironment,
        context: EvaluationContext,
        localID: UUID,
        customAttributeResolver: @escaping EvaluationContext.CustomAttributeResolver
    ) -> String {
        let evaluator = FlagEvaluator(
            configuration: configuration,
            environment: environment,
            context: context,
            localID: localID,
            customAttributeResolver: customAttributeResolver
        )
        let sortedKeys = configuration.flags.keys.sorted()
        var widths: [(key: String, width: Int)] = []
        var selections: [String: Int] = [:]
        for key in sortedKeys {
            widths.append((key: key, width: bitWidth(evaluator.pathCount(flagKey: key))))
            selections[key] = evaluator.resolvePathIndex(flagKey: key)
        }
        return encode(
            configVersion: configuration.configVersion,
            environmentIndex: environment.fingerprintIndex,
            flagWidthsSortedByKey: widths,
            selections: selections
        )
    }
}

extension BuntingEnvironment {
    /// The environment's index in a config fingerprint (`0` development, `1` beta, `2` production).
    var fingerprintIndex: Int {
        switch self {
        case .development: return 0
        case .beta: return 1
        case .production: return 2
        }
    }
}
