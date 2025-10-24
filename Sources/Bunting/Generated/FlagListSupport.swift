import Foundation

/// Simple model used by generated code to present all flags and their current values.
public struct FlagListItem {
    public let key: String
    public let type: String
    public let makeString: (Bunting) -> String

    public init(key: String, type: String, makeString: @escaping (Bunting) -> String) {
        self.key = key
        self.type = type
        self.makeString = makeString
    }
}

