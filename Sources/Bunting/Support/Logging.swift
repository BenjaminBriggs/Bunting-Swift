import Foundation
import OSLog

enum BuntingLog {
    static let core = Logger(subsystem: "com.bunting.sdk", category: "core")
    static let config = Logger(subsystem: "com.bunting.sdk", category: "config")
    static let network = Logger(subsystem: "com.bunting.sdk", category: "network")
}

