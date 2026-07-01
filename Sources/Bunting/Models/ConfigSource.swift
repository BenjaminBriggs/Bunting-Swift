import Foundation

/// Where the active configuration came from.
///
/// Exposed via ``Bunting/configSource`` so integrators and the debug UI can
/// tell a freshly fetched config from a disk cache or the bundled seed.
public enum ConfigSource: String, Sendable {
    /// Fetched from the remote endpoint and signature-verified in this process.
    case fetched
    /// Loaded from the on-disk cache; its persisted signature was re-verified on load.
    case cache
    /// Loaded from the bundled seed (`BuntingConfig.json`); not signature-verified
    /// at runtime — its integrity story is verification at fetch time by
    /// `bunting-cli` plus the app bundle's code signature.
    case seed
}
