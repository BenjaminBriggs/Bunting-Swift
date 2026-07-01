import Foundation
import Testing

@testable import Bunting

/// Direct coverage of `MemoizationCache`'s hit/miss and invalidation contract.
/// `MemoizationCache` is `@MainActor`-isolated, so this suite runs on the
/// main actor.
@Suite("MemoizationCache")
@MainActor
struct MemoizationCacheTests {

    private func makeKey(
        flagKey: String = "feature/flag",
        environment: BuntingEnvironment = .development,
        contextHash: Int = 1,
        overridesVersion: Int = 0,
        configVersion: String = "2025-01-01.1"
    ) -> MemoizationCache.CacheKey {
        MemoizationCache.CacheKey(
            flagKey: flagKey,
            environment: environment,
            contextHash: contextHash,
            overridesVersion: overridesVersion,
            configVersion: configVersion
        )
    }

    @Test("Same key returns the cached value on subsequent get")
    func sameKeyIsCacheHit() throws {
        let cache = MemoizationCache()
        let key = makeKey()

        #expect(cache.get(key) == nil)  // miss before anything is stored

        cache.set(key, value: .boolean(true))

        #expect(cache.get(key) == .boolean(true))

        let stats = cache.stats()
        #expect(stats.hits == 1)
        #expect(stats.misses == 1)
    }

    @Test("Different context hash produces a different cache entry (miss)")
    func differentContextHashIsCacheMiss() throws {
        let cache = MemoizationCache()
        let baseKey = makeKey(contextHash: 111)
        let changedKey = makeKey(contextHash: 222)

        cache.set(baseKey, value: .string("us-value"))

        // Same flag/environment/overridesVersion/configVersion, but a
        // different context hash (e.g. a changed custom attribute, platform,
        // or app version) must not reuse the stale entry.
        #expect(cache.get(changedKey) == nil)
        #expect(cache.get(baseKey) == .string("us-value"))
    }

    @Test("Different config version produces a different cache entry (miss)")
    func differentConfigVersionIsCacheMiss() throws {
        // Pin the contract that CacheKey.configVersion participates in
        // equality — a new config, even without an explicit invalidateAll(),
        // naturally misses because the key no longer matches.
        let cache = MemoizationCache()
        let oldVersionKey = makeKey(configVersion: "2025-01-01.1")
        let newVersionKey = makeKey(configVersion: "2025-01-02.1")

        cache.set(oldVersionKey, value: .integer(1))

        #expect(cache.get(newVersionKey) == nil)
    }

    @Test("invalidateAll clears every cached entry")
    func invalidateAllClearsCache() throws {
        let cache = MemoizationCache()
        let keyA = makeKey(flagKey: "flag/a")
        let keyB = makeKey(flagKey: "flag/b")

        cache.set(keyA, value: .boolean(true))
        cache.set(keyB, value: .boolean(false))

        cache.invalidateAll()

        #expect(cache.get(keyA) == nil)
        #expect(cache.get(keyB) == nil)
    }

    @Test("invalidate(flagKey:) only removes entries for that flag")
    func invalidateSingleFlagKeyOnlyRemovesMatchingEntries() throws {
        let cache = MemoizationCache()
        let targetKey = makeKey(flagKey: "flag/target")
        let otherKey = makeKey(flagKey: "flag/other")

        cache.set(targetKey, value: .string("target-value"))
        cache.set(otherKey, value: .string("other-value"))

        cache.invalidate(flagKey: "flag/target")

        #expect(cache.get(targetKey) == nil)
        #expect(cache.get(otherKey) == .string("other-value"))
    }
}
