import Foundation

/// Thread-safe memoization cache for flag evaluation results
/// Invalidates when configuration, overrides, or context changes
actor MemoizationCache {

    private var cache: [CacheKey: FlagValue] = [:]
    private var hits: Int = 0
    private var misses: Int = 0

    /// Cache key that captures all factors affecting flag evaluation
    struct CacheKey: Hashable, Sendable {
        let flagKey: String
        let environment: BuntingEnvironment
        let contextHash: Int
        let overridesVersion: Int
        let configVersion: String
    }

    /// Retrieve a cached flag value
    func get(_ key: CacheKey) -> FlagValue? {
        if let value = cache[key] {
            hits += 1
            return value
        }
        misses += 1
        return nil
    }

    /// Store a flag value in the cache
    func set(_ key: CacheKey, value: FlagValue) {
        cache[key] = value
    }

    /// Invalidate all cached values
    /// Call this when configuration or overrides change
    func invalidateAll() {
        cache.removeAll(keepingCapacity: true)
    }

    /// Invalidate cache entries for a specific flag
    func invalidate(flagKey: String) {
        cache = cache.filter { $0.key.flagKey != flagKey }
    }

    /// Get cache statistics for debugging
    func stats() -> CacheStats {
        CacheStats(
            size: cache.count,
            hits: hits,
            misses: misses,
            hitRate: hits + misses > 0 ? Double(hits) / Double(hits + misses) : 0
        )
    }

    /// Reset statistics
    func resetStats() {
        hits = 0
        misses = 0
    }
}

/// Cache statistics for monitoring performance
struct CacheStats: Sendable {
    let size: Int
    let hits: Int
    let misses: Int
    let hitRate: Double
}
