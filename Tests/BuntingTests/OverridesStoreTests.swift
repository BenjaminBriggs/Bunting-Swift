import Foundation
import Testing

@testable import Bunting

/// Direct coverage of `OverridesStore`'s UserDefaults-backed persistence.
/// Each test uses its own UserDefaults suite (named per-test with a UUID) so
/// tests can run in parallel without clobbering each other's state, and
/// removes the suite's persistent domain when done.
///
/// Tests that simulate re-instantiation (an app restart) create a *new*
/// `UserDefaults(suiteName:)` instance per store rather than sharing one
/// local variable — both because that matches what actually happens across
/// launches, and because Swift 6 region isolation forbids sending the same
/// local value into two separate actor-isolated `OverridesStore` inits.
@Suite("OverridesStore")
struct OverridesStoreTests {

    private func makeSuiteName() -> String {
        "bunting-overrides-test-\(UUID().uuidString)"
    }

    private func defaults(for suiteName: String) -> UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test("Set override is readable back")
    func setOverrideIsReadableBack() async throws {
        let suiteName = makeSuiteName()
        defer { cleanup(suiteName) }

        let store = OverridesStore(userDefaults: defaults(for: suiteName))
        await store.setOverride("feature/dark_mode", value: .bool(true))

        let value = await store.getOverride("feature/dark_mode")
        #expect(value?.asAny as? Bool == true)
    }

    @Test("Overrides survive store re-instantiation against the same UserDefaults suite")
    func overridesSurviveReinstantiation() async throws {
        let suiteName = makeSuiteName()
        defer { cleanup(suiteName) }

        let store = OverridesStore(userDefaults: defaults(for: suiteName))
        await store.setOverride("pricing/tier", value: .string("premium"))

        // A fresh store instance backed by the same UserDefaults suite (as
        // happens across app launches) must see the persisted value once it
        // loads.
        let reloadedStore = OverridesStore(userDefaults: defaults(for: suiteName))
        await reloadedStore.loadOverridesIfNeeded()

        let value = await reloadedStore.getOverride("pricing/tier")
        #expect(value?.asAny as? String == "premium")
    }

    @Test("Clearing a single override removes only that flag")
    func clearSingleOverrideRemovesOnlyThatFlag() async throws {
        let suiteName = makeSuiteName()
        defer { cleanup(suiteName) }

        let store = OverridesStore(userDefaults: defaults(for: suiteName))
        await store.setOverride("flag/a", value: .bool(true))
        await store.setOverride("flag/b", value: .bool(false))

        await store.clearOverride("flag/a")

        let a = await store.getOverride("flag/a")
        let b = await store.getOverride("flag/b")
        #expect(a == nil)
        #expect(b?.asAny as? Bool == false)
    }

    @Test("Clearing all overrides empties the store and persists the empty state")
    func clearAllEmptiesStore() async throws {
        let suiteName = makeSuiteName()
        defer { cleanup(suiteName) }

        let store = OverridesStore(userDefaults: defaults(for: suiteName))
        await store.setOverride("flag/a", value: .bool(true))
        await store.setOverride("flag/b", value: .int(42))

        await store.clearAll()

        let all = await store.getAllOverrides()
        #expect(all.isEmpty)

        // Confirm the empty state was actually persisted, not just held
        // in-memory — a fresh store over the same suite should also be empty.
        let reloadedStore = OverridesStore(userDefaults: defaults(for: suiteName))
        await reloadedStore.loadOverridesIfNeeded()
        let reloadedAll = await reloadedStore.getAllOverrides()
        #expect(reloadedAll.isEmpty)
    }

    @Test("An unsupported persisted value type is silently dropped on load")
    func unsupportedPersistedValueTypeIsDroppedOnLoad() async throws {
        let suiteName = makeSuiteName()
        defer { cleanup(suiteName) }

        // Simulate a corrupted/foreign UserDefaults entry: OverrideValue only
        // recognizes Bool, Int, Double, String, and Date (see
        // OverrideValue.init(_:)). Write a type it doesn't understand (an
        // array) directly under the same key the store uses.
        let rawDefaults = defaults(for: suiteName)
        rawDefaults.set(["flag/broken": [1, 2, 3]], forKey: "bunting.overrides")

        let store = OverridesStore(userDefaults: defaults(for: suiteName))
        await store.loadOverridesIfNeeded()

        let value = await store.getOverride("flag/broken")
        #expect(value == nil)
    }

    @Test("Setting an override for a flag replaces its previous value")
    func settingOverrideReplacesPreviousValue() async throws {
        let suiteName = makeSuiteName()
        defer { cleanup(suiteName) }

        let store = OverridesStore(userDefaults: defaults(for: suiteName))
        await store.setOverride("pricing/tier", value: .string("free"))
        await store.setOverride("pricing/tier", value: .string("premium"))

        let value = await store.getOverride("pricing/tier")
        #expect(value?.asAny as? String == "premium")
    }
}
