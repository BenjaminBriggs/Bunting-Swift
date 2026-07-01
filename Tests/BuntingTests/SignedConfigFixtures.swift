import Foundation

/// Signed config.json + detached JWS + SPKI public key fixtures shared across
/// in-process (ConfigStoreTests) and subprocess (CLITests) signature tests.
/// Generated offline with openssl, in the same detached RFC 7797 form the
/// admin publishes. Both fixtures' decoded config bodies carry every field
/// bunting-cli's `BuntingConfiguration` decoder requires (schema_version,
/// config_version, published_at, app_identifier), so they support a genuine
/// end-to-end success path, not just signature verification in isolation.
enum SignedConfigFixture {
    // MARK: - Primary fixture: kid "test-key"

    /// base64 of the exact config.json bytes that were signed.
    static let configB64 =
        "eyJzY2hlbWFfdmVyc2lvbiI6MSwiY29uZmlnX3ZlcnNpb24iOiIyMDI2LTA3LTAxLjEiLCJwdWJsaXNoZWRfYXQiOiIyMDI2LTA3LTAxVDAwOjAwOjAwWiIsImFwcF9pZGVudGlmaWVyIjoidGVzdC1hcHAiLCJmbGFncyI6e30sInRlc3RzIjp7fSwicm9sbG91dHMiOnt9fQ=="

    /// base64 of the SPKI public-key PEM matching `jws`.
    static let pemB64 =
        "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUFrdjBRR3VUT3V2TGVnZ25MV1c0RwpmVjNVYm4zKzRtTzhsZTB0d2daRkVwRlVMMzBkOEtoY1BYZk0yanVqa0hSSDNWRUlnMG5xaXRGUkdtNitpQzNSCkdJZ1RLbUlIdnNoMi9zaVlvZUpKNnk4Ylc0Vmo1RWtSSFFuMGpBV2V2VnY2c2pySHpqbEJ2TlV1SXdWMnlCSFEKN2tvV1VISGJOS0NwQkh5N3BiaDB1TUNMckkwazBUSFY2dTQ2SmJYTXFmSzFNeFdzNmhRczgzaVJac2RlbnY1TQpZUlpFT3NkYXdNUnhEUXlDemUrekhvV2hqZCtORjF4aEJIOWcvWkF3dHVKTWZwZzI2S0J6TTFuTDhZSm4vRTJiCjMyZkVQTFBYbGt1VzViWHB4U05OMk9kdjcrbXJQd2JHY3VEUXJQekJLa1RnUU1NaXZqUmV3RWQxUUNNbHdHOFIKNndJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg=="

    /// Compact detached JWS over the primary fixture, header kid "test-key".
    static let jws =
        "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2V5IiwiYjY0IjpmYWxzZSwiY3JpdCI6WyJiNjQiXX0..IXa6m5ELaRplNOXna1nbZRa-9mV0V_LAcShSCZveSoVUz9Fy2KEHaVeQYGz06iaD_lDaafWkV04RnWOFmuZaFHbzlJbZm1IHXzBlbNEIIz5_4O3wmP2kYMEAt8c9mtFNHkcTVjROopAPE8gHNpmNc8gHmPpX7zPjt9DNW0MyK1-8cb6l0RCoDWfqkE64yXZjt-DprKGUM-PLkdSKAWuy6rsxgQ4gU3gLen0rOmzWrA7liphXmXZbzCu0lb9XiQjONGC94KQbfwS0FYpMAcEvFlG5hF-vCgbcnfeGwwNMUAueo2Tk_8OwQoPgrrH04rfW-gMFmvhQ5hBMhp2besEwcQ"

    // MARK: - Secondary fixture: kid "test-key-2", different key pair.

    static let secondaryConfigB64 =
        "eyJzY2hlbWFfdmVyc2lvbiI6MiwiY29uZmlnX3ZlcnNpb24iOiIyMDI2LTA3LTAxLjIiLCJwdWJsaXNoZWRfYXQiOiIyMDI2LTA3LTAxVDAwOjAwOjAwWiIsImFwcF9pZGVudGlmaWVyIjoidGVzdC1hcHAiLCJmbGFncyI6e30sInRlc3RzIjp7fSwicm9sbG91dHMiOnt9fQ=="

    static let secondaryPemB64 =
        "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUF5cGpMcXN0VFZpY2g1Wm9FVnRsMApyZEsxZVZweFhqTW1yVy9QN2dtYnZSdGtvTEMyS1U5clY3Mm1QaFlVMVBFV0dmWGdKYk93aDVxRDU1MkxheTFPCklvUGtZZWM3ZE5kWHRvNnVpRFpHdXhvVy9qaWtDRmxVSk9qcFNrZkZ2LzZmV1Z5bHV6cmxEc0NGUEFjR1ZVZEoKZ0ZNb3VHcVBXZDNLcmtiQ05PVmUveGt0VTNuQUZzdW93L2NzZkVaNWZIaExnbzdjQ2NvUEpENE1Xek04eWZTNAp3cEhsWjZwMDY0QVV2NlMyY05ZQ1ZvSUtMQXhIWlc3TXJMNXVBelNGUFZ5MFl6NG5vc2lqeUQySWtyZXdkSnhUCnQyMllVK3Y5WTBYcTRsOWd3NmdMMWVrZ0JUOVRZUWtZUXg2anlBeUd1SFhQOEtXcmFaN3c1bjBOVFRkTEFqTjAKaFFJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg=="

    static let secondaryJWS =
        "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2V5LTIiLCJiNjQiOmZhbHNlLCJjcml0IjpbImI2NCJdfQ..rgRnuIxa_UjpeK1nNCnwysqTpLugggv-Lz_r6uupX4nVhtubTEYj-Yvuz-6Q_-QK48XYlXO4xh73jQxba5BGxBgkwzO1GRtmiGB1xee_RivtP6feDecTGXkKWI-jO1dT1sTW1ZzI-O6NPovOoeYmueiC1WCa5kAjZrqS6xU8q_8j_xFPtBgzh4QQ0i2BQh0H6eBvwc9Ah1kAapcuMPPvUGepM9m3LBcaiOU6dY9_OuOgPmFkp2KIb9g7ZXzL7KuPuKYW8r3axr6P19ravZ29cbyuN-B-wXRWRdqQUgEprXfW_X7i-oJsgZQzVp5CqTUbj9Ucy1qI7sSfi4uWsXrKtg"

    // MARK: - Decoded convenience accessors

    static var configData: Data { Data(base64Encoded: configB64)! }
    static var pem: String { String(data: Data(base64Encoded: pemB64)!, encoding: .utf8)! }
    static var secondaryPem: String {
        String(data: Data(base64Encoded: secondaryPemB64)!, encoding: .utf8)!
    }
}
