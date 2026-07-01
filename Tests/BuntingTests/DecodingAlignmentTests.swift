import Foundation
import Testing

@testable import Bunting

/// Covers artifact decoding/evaluation mismatches found in the cross-repo
/// audit between the admin's published `config.json` and this SDK's decoders.
@Suite("Decoding Alignment")
struct DecodingAlignmentTests {

    // MARK: - Date flag values with fractional seconds

    @Test("Date flag value with fractional seconds decodes as .date")
    func dateFlagValueWithFractionalSeconds() throws {
        let json = Data("\"2026-07-01T10:00:04.796Z\"".utf8)
        let value = try JSONDecoder().decode(FlagValue.self, from: json)

        guard case .date = value else {
            Issue.record("Expected .date, got \(value)")
            return
        }
    }

    @Test("Date flag value without fractional seconds decodes as .date")
    func dateFlagValueWithoutFractionalSeconds() throws {
        let json = Data("\"2026-07-01T10:00:04Z\"".utf8)
        let value = try JSONDecoder().decode(FlagValue.self, from: json)

        guard case .date = value else {
            Issue.record("Expected .date, got \(value)")
            return
        }
    }

    // MARK: - Whole-number double coercion

    @Test("Whole-number double flag value coerces to Double via the accessor unwrap")
    func wholeNumberDoubleCoercesFromInteger() throws {
        // A double flag whose value is a whole number serializes as `2` in
        // JSON and decodes as `.integer` per FlagValue's decode order (which
        // must not change — int flags rely on it). The double accessor's
        // extraction layer must still coerce it.
        let json = Data("2".utf8)
        let value = try JSONDecoder().decode(FlagValue.self, from: json)

        guard case .integer = value else {
            Issue.record("Expected .integer (decode order unchanged), got \(value)")
            return
        }
        #expect(value.doubleValue == 2.0)
    }

    @Test("Int flag value still returns Int correctly")
    func intFlagValueUnaffected() throws {
        let json = Data("2".utf8)
        let value = try JSONDecoder().decode(FlagValue.self, from: json)

        #expect(value.intValue == 2)
    }

    @Test("Fractional double flag value is unaffected")
    func fractionalDoubleValueUnaffected() throws {
        let json = Data("2.5".utf8)
        let value = try JSONDecoder().decode(FlagValue.self, from: json)

        guard case .double = value else {
            Issue.record("Expected .double, got \(value)")
            return
        }
        #expect(value.doubleValue == 2.5)
    }

    // MARK: - schema_version validation

    private func configJSON(schemaVersion: Int) -> Data {
        Data(
            """
            {
                "schema_version": \(schemaVersion),
                "config_version": "2026-07-01.1",
                "published_at": "2026-07-01T00:00:00Z",
                "app_identifier": "test-app",
                "flags": {},
                "tests": {},
                "rollouts": {}
            }
            """.utf8)
    }

    @Test("schema_version 1 decodes successfully")
    func schemaVersionOneSucceeds() throws {
        let config = try JSONDecoder().decode(BuntingConfiguration.self, from: configJSON(schemaVersion: 1))
        #expect(config.schemaVersion == 1)
    }

    @Test("schema_version 2 throws a decoding error")
    func schemaVersionTwoThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BuntingConfiguration.self, from: configJSON(schemaVersion: 2))
        }
    }
}
