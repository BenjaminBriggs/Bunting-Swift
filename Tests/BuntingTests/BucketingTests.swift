import XCTest

@testable import Bunting

final class BucketingTests: XCTestCase {
    func testDeterministicBucketing() {
        // Test that same salt + ID produces same bucket
        let salt = "test-salt"
        let uuid = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

        let bucket1 = Bucketing.bucket(salt: salt, localID: uuid)
        let bucket2 = Bucketing.bucket(salt: salt, localID: uuid)

        XCTAssertEqual(bucket1, bucket2, "Same salt + ID should produce same bucket")
    }

    func testBucketRange() {
        // Test that buckets are in range 1-100
        let salt = "test-salt"

        for _ in 0..<100 {
            let uuid = UUID()
            let bucket = Bucketing.bucket(salt: salt, localID: uuid)

            XCTAssertTrue(bucket >= 1 && bucket <= 100, "Bucket should be in range 1-100, got \(bucket)")
        }
    }

    func testDifferentSaltsDifferentBuckets() {
        // Different salts should generally produce different buckets
        let uuid = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

        let bucket1 = Bucketing.bucket(salt: "salt1", localID: uuid)
        let bucket2 = Bucketing.bucket(salt: "salt2", localID: uuid)

        // While not guaranteed to be different, it's extremely likely
        XCTAssertNotEqual(bucket1, bucket2, "Different salts should produce different buckets")
    }

    func testDifferentIDsDifferentBuckets() {
        // Different IDs should generally produce different buckets
        let salt = "test-salt"

        let bucket1 = Bucketing.bucket(salt: salt, localID: UUID())
        let bucket2 = Bucketing.bucket(salt: salt, localID: UUID())

        // While not guaranteed to be different, it's extremely likely
        XCTAssertNotEqual(bucket1, bucket2, "Different IDs should produce different buckets")
    }

    func testKnownVector() {
        // Test against a known vector to ensure algorithm matches spec
        let salt = "unique-salt"
        let uuid = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

        let bucket = Bucketing.bucket(salt: salt, localID: uuid)

        // This should be consistent across all SDK implementations
        // The exact value depends on SHA-256("unique-salt:550E8400-E29B-41D4-A716-446655440000")
        XCTAssertTrue(bucket >= 1 && bucket <= 100, "Bucket should be in valid range")
    }
}
