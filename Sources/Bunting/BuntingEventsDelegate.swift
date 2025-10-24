//
//  BuntingEventsDelegate.swift
//  Bunting
//
//  Protocol for observing Bunting lifecycle events
//

import Foundation

/// Delegate protocol for observing Bunting configuration and evaluation events
///
/// Implement this protocol to receive notifications about:
/// - Configuration fetch lifecycle (start, completion, errors)
/// - Signature verification results
/// - Cached configuration loading
/// - Fallback to default values
/// - Override changes
///
/// Usage:
/// ```swift
/// class MyBuntingObserver: BuntingEventsDelegate {
///     func didStartFetch(url: URL) {
///         os_log("Fetching config from %@", url.absoluteString)
///     }
///
///     func didCompleteFetch(success: Bool, error: Error?) {
///         if success {
///             os_log("Config fetch succeeded")
///         } else {
///             os_log("Config fetch failed: %@", error?.localizedDescription ?? "unknown")
///         }
///     }
///
///     // ... implement other methods
/// }
///
/// // Set the delegate
/// Bunting.shared.eventsDelegate = MyBuntingObserver()
/// ```
///
/// Note: All delegate methods are called on the main actor.
@MainActor
public protocol BuntingEventsDelegate: AnyObject, Sendable {
    /// Called when a configuration fetch starts
    ///
    /// - Parameter url: The URL being fetched
    func didStartFetch(url: URL)

    /// Called when a configuration fetch completes
    ///
    /// - Parameters:
    ///   - success: Whether the fetch succeeded
    ///   - error: The error if fetch failed, nil otherwise
    func didCompleteFetch(success: Bool, error: Error?)

    /// Called when signature verification completes
    ///
    /// - Parameter success: Whether signature verification succeeded
    func didVerifySignature(success: Bool)

    /// Called when a cached configuration is loaded
    ///
    /// - Parameter version: The version of the cached configuration
    func didLoadCachedConfig(version: String)

    /// Called when a flag evaluation falls back to the default value
    ///
    /// This occurs when:
    /// - No configuration is loaded
    /// - The flag doesn't exist in the configuration
    /// - No variant matches the evaluation context
    ///
    /// - Parameter flagKey: The key of the flag that fell back to default
    func didFallbackToDefault(flagKey: String)

    /// Called when an override is set or changed
    ///
    /// - Parameters:
    ///   - flagKey: The key of the flag being overridden
    ///   - value: The new override value, or nil if the override is being cleared
    func didChangeOverride(flagKey: String, value: Any?)
}

// MARK: - Optional Methods

/// Default implementations for optional delegate methods
@MainActor
extension BuntingEventsDelegate {
    public func didStartFetch(url: URL) {}
    public func didCompleteFetch(success: Bool, error: Error?) {}
    public func didVerifySignature(success: Bool) {}
    public func didLoadCachedConfig(version: String) {}
    public func didFallbackToDefault(flagKey: String) {}
    public func didChangeOverride(flagKey: String, value: Any?) {}
}
