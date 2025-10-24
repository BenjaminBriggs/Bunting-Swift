import Foundation

/// The root configuration object containing all flags, cohorts, tests, and rollouts
public struct BuntingConfiguration: Decodable, Sendable {
    public let schemaVersion: Int
    public let configVersion: String
    public let publishedAt: Date
    public let appIdentifier: String
    public let cohorts: [String: Cohort]
    public let flags: [String: Flag]
    public let tests: [String: Test]
    public let rollouts: [String: Rollout]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case configVersion = "config_version"
        case publishedAt = "published_at"
        case appIdentifier = "app_identifier"
        case cohorts
        case flags
        case tests
        case rollouts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        configVersion = try container.decode(String.self, forKey: .configVersion)
        appIdentifier = try container.decode(String.self, forKey: .appIdentifier)

        // Decode publishedAt as ISO8601
        let publishedAtString = try container.decode(String.self, forKey: .publishedAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: publishedAtString) {
            publishedAt = date
        } else {
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: publishedAtString) {
                publishedAt = date
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .publishedAt,
                    in: container,
                    debugDescription: "Invalid ISO8601 date format"
                )
            }
        }

        cohorts = try container.decode([String: Cohort].self, forKey: .cohorts)
        flags = try container.decode([String: Flag].self, forKey: .flags)
        tests = try container.decode([String: Test].self, forKey: .tests)
        rollouts = try container.decode([String: Rollout].self, forKey: .rollouts)
    }
}
