//

import SwiftUI
import Bunting

@Observable
final class ViewModel {
    
    var isRefreshing = false
    var welcomeMessage = "Loading..."
    var maxUploadSize = 0
    var discountPercentage = 0.0
 
    // MARK: - Methods
    
    /// Loads all flag values from Bunting
    /// This demonstrates the different accessor methods for each flag type
    func loadFlags() async {
        // Get a reference to the shared Bunting instance
        let bunting = Bunting.shared
        
        // MARK: String Flags
        // Use the string() method
        welcomeMessage = bunting.ui.welcomeMessage
        
        // MARK: Integer Flags
        // Use the int() method for whole numbers
        maxUploadSize = bunting.features.maxUploadSize
        
        // MARK: Double Flags
        // Use the double() method for decimal numbers
        discountPercentage = bunting.features.discountPercentage
    }
    
    /// Manually refreshes the configuration from the backend
    /// This respects rate limiting configured in BuntingConfig.plist
    func refreshConfiguration() async {
        isRefreshing = true
        
        let bunting = Bunting.shared
        
        // Trigger a refresh from the backend
        // This will:
        // 1. Check if enough time has passed since last fetch (rate limiting)
        // 2. Make a conditional GET request with ETag
        // 3. Verify the signature if new data is received
        // 4. Update the cached configuration
        await bunting.refresh()
        
        // Reload flag values to reflect any changes
        await loadFlags()
        
        isRefreshing = false
    }
}
