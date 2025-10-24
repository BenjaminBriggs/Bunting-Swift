//
//  BuntingExampleApp.swift
//  BuntingExample
//
//  Created by Benjamin Briggs on 24/10/2025.
//

import Bunting
import SwiftUI

@main
struct BuntingExampleApp: App {

    init() {
        // MARK: - Bunting SDK Configuration
        // Configure Bunting when the app launches.
        // This is the only setup required - all flag access happens through Bunting.shared

        #if DEBUG
            // In debug builds, use the development environment
            // This lets you test flags in a separate configuration from production
            try? Bunting.configure(environment: .development)
        #else
            // In release builds, use the production environment
            try? Bunting.configure(environment: .production)
        #endif

        // MARK: Alternative Configuration Options

        // You can also provide custom attributes for advanced targeting:
        // try? Bunting.configure(
        //     environment: .production,
        //     customAttributes: { attribute in
        //         // Return true/false based on your app's state
        //         switch attribute {
        //         case "is_premium":
        //             return UserDefaults.standard.bool(forKey: "isPremium")
        //         case "has_completed_onboarding":
        //             return UserDefaults.standard.bool(forKey: "onboardingComplete")
        //         default:
        //             return false
        //         }
        //     }
        // )

        // Or share identity across apps with a keychain access group:
        // try? Bunting.configure(
        //     environment: .production,
        //     keychainAccessGroup: "group.com.yourcompany.shared"
        // )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
