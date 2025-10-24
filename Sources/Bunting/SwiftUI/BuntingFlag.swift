import Foundation
import Observation
import SwiftUI

// MARK: - SwiftUI Environment Integration

/// Environment key for accessing the Bunting instance
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct BuntingKey: EnvironmentKey {
    public static let defaultValue: Bunting = {
        // Access Bunting.shared on MainActor in a nonisolated context
        // This is safe because SwiftUI accesses environment values on the main thread
        MainActor.assumeIsolated {
            Bunting.shared
        }
    }()
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension EnvironmentValues {
    /// Access to the Bunting instance via SwiftUI environment
    ///
    /// Usage:
    /// ```swift
    /// @Environment(\.bunting) var bunting
    /// ```
    public var bunting: Bunting {
        get { self[BuntingKey.self] }
        set { self[BuntingKey.self] = newValue }
    }
}

// MARK: - Property Wrapper

/// Property wrapper that resolves a flag value via a generated descriptor key path.
///
/// Usage:
///   @BuntingFlag(\.features.maxItems) var maxItems: Int
///
/// Note: We use the name BuntingFlag to avoid colliding with the Bunting class type.
@propertyWrapper
@MainActor
public struct BuntingFlag<T> {
    private let keyPath: KeyPath<BuntingPaths, FlagDescriptor<T>>

    public init(_ keyPath: KeyPath<BuntingPaths, FlagDescriptor<T>>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: T {
        let client = Bunting.shared
        let root = BuntingPaths(bunting: client)
        let descriptor = root[keyPath: keyPath]
        return descriptor.resolve(client)
    }

    /// Access to the underlying descriptor (key, defaults, etc.)
    public var projectedValue: FlagDescriptor<T> {
        let client = Bunting.shared
        let root = BuntingPaths(bunting: client)
        return root[keyPath: keyPath]
    }
}
