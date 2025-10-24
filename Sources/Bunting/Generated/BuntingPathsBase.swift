import Foundation

/// Root container for generated flag descriptors.
/// Codegen will extend this type with nested namespaces and properties.
public struct BuntingPaths {
    public let bunting: Bunting
    public init(bunting: Bunting) { self.bunting = bunting }
}

/// A descriptor for a typed flag.
public struct FlagDescriptor<T> {
    public let key: String
    public let defaultValue: T
    public let resolve: (Bunting) -> T

    public init(key: String, defaultValue: T, resolve: @escaping (Bunting) -> T) {
        self.key = key
        self.defaultValue = defaultValue
        self.resolve = resolve
    }
}
