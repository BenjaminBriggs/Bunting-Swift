import Foundation
import Testing

@testable import Bunting

/// `Bunting`'s typed accessors (`bool`, `string`, `int`, `double`, `date`,
/// `jsonData`) each do `evaluateFlagSync(...)?.<caseValue> ?? defaultValue`
/// (see `Bunting.swift`). `Bunting` itself can't be instantiated in-process —
/// its initializer is `private` and requires a `BuntingConfig.plist` in
/// `Bundle.main` (absent under `swift test`) plus live Keychain/network
/// access — so this suite pins the wrong-type-returns-nil contract directly
/// on the `FlagValue` extension accessors, which is the exact code path the
/// facade falls back through. See the task report for the full facade-level
/// gap writeup.
@Suite("FlagValue typed accessors")
struct FlagValueAccessorTests {

    @Test("boolValue is nil for a non-boolean case")
    func boolValueNilForWrongType() throws {
        #expect(FlagValue.string("true").boolValue == nil)
        #expect(FlagValue.boolean(true).boolValue == true)
    }

    @Test("intValue is nil for a non-integer case")
    func intValueNilForWrongType() throws {
        #expect(FlagValue.string("42").intValue == nil)
        #expect(FlagValue.integer(42).intValue == 42)
    }

    @Test("stringValue is nil for a non-string case")
    func stringValueNilForWrongType() throws {
        #expect(FlagValue.boolean(true).stringValue == nil)
        #expect(FlagValue.string("hello").stringValue == "hello")
    }

    @Test("dateValue is nil for a non-date case")
    func dateValueNilForWrongType() throws {
        #expect(FlagValue.string("2026-01-01T00:00:00Z").dateValue == nil)
        let date = Date()
        #expect(FlagValue.date(date).dateValue == date)
    }

    @Test("jsonData is nil for a non-json case")
    func jsonDataNilForWrongType() throws {
        #expect(FlagValue.string("{}").jsonData == nil)
        let jsonValue = FlagValue.json("{\"a\":1}")
        #expect(jsonValue.jsonData == Data("{\"a\":1}".utf8))
    }

    @Test("doubleValue coerces a whole-number .integer, matching the accessor's documented behavior")
    func doubleValueCoercesInteger() throws {
        #expect(FlagValue.integer(2).doubleValue == 2.0)
        #expect(FlagValue.double(2.5).doubleValue == 2.5)
        #expect(FlagValue.string("2.5").doubleValue == nil)
    }
}
