import Foundation
import Combine

// MARK: - SwipeData Singleton
class SwipeData: ObservableObject {
    @Published var swipeCount: Int {
        didSet {
            KeychainHelper.save(String(swipeCount), forKey: "swipeCount")
            NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
        }
    }
    
    @Published var totalLifetimeSwipes: Int {
        didSet {
            KeychainHelper.save(String(totalLifetimeSwipes), forKey: "totalLifetimeSwipes")
        }
    }
    
    @Published var extraSwipes: Int {
        didSet {
            KeychainHelper.save(String(extraSwipes), forKey: "extraSwipes")
            NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
        }
    }
    
    @Published var isPremium: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    // Timer for automatic daily reset check
    private var dailyResetTimer: Timer?
    
    static let shared = SwipeData()
    
    private init() {
        // Load from Keychain instead of UserDefaults
        self.swipeCount = Int(KeychainHelper.get(forKey: "swipeCount") ?? "0") ?? 0
        self.totalLifetimeSwipes = Int(KeychainHelper.get(forKey: "totalLifetimeSwipes") ?? "0") ?? 0
        self.extraSwipes = Int(KeychainHelper.get(forKey: "extraSwipes") ?? "0") ?? 0
        self.isPremium = StoreKitManager.shared.isPremium
        
        StoreKitManager.shared.$isPremium
            .receive(on: RunLoop.main)
            .assign(to: \.isPremium, on: self)
            .store(in: &cancellables)
        
        // Migrate existing UserDefaults data to Keychain if needed
        migrateUserDefaultsToKeychain()
        
        resetIfNeeded()
        setupDailyResetTimer()
    }
    
    deinit {
        dailyResetTimer?.invalidate()
    }
    
    // MARK: - Migration Helper
    private func migrateUserDefaultsToKeychain() {
        // Only migrate if Keychain is empty and UserDefaults has data
        if KeychainHelper.get(forKey: "swipeCount") == nil {
            let oldSwipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
            let oldTotalSwipes = UserDefaults.standard.integer(forKey: "totalLifetimeSwipes")
            let oldExtraSwipes = UserDefaults.standard.integer(forKey: "extraSwipes")
            
            if oldSwipeCount > 0 || oldTotalSwipes > 0 || oldExtraSwipes > 0 {
                // Migrate to Keychain
                KeychainHelper.save(String(oldSwipeCount), forKey: "swipeCount")
                KeychainHelper.save(String(oldTotalSwipes), forKey: "totalLifetimeSwipes")
                KeychainHelper.save(String(oldExtraSwipes), forKey: "extraSwipes")
                
                // Update published properties
                self.swipeCount = oldSwipeCount
                self.totalLifetimeSwipes = oldTotalSwipes
                self.extraSwipes = oldExtraSwipes
                
                
                // Optionally clear UserDefaults
                UserDefaults.standard.removeObject(forKey: "swipeCount")
                UserDefaults.standard.removeObject(forKey: "totalLifetimeSwipes")
                UserDefaults.standard.removeObject(forKey: "extraSwipes")
            }
        }
    }
    
    // MARK: - Swipe Handling
    func incrementSwipeCount() {
        // ALWAYS increment total lifetime swipes for stats (all users)
        totalLifetimeSwipes += 1
        
        if !isPremium {
            if swipeCount < 100 {
                // Use free swipe
                swipeCount += 1
            } else if extraSwipes > 0 {
                // Use extra swipe, don't increment daily counter but still count for stats
                extraSwipes -= 1
            } else {
                // No swipes available - this shouldn't happen if UI prevents it
                // Don't increment anything if no swipes available
                totalLifetimeSwipes -= 1  // Rollback the increment
                return
            }
        } else {
            // Premium users: increment daily count for consistency (no limit)
            swipeCount += 1
        }
        
        // Mark that swipes have been used
        if totalLifetimeSwipes > 0 {
            markSwipesUsed()
        }
    }
    
    func addExtraSwipes(_ count: Int) {
        extraSwipes += count
    }
    
    func refreshFromUserDefaults() {
        // Since we're using Keychain now, refresh from Keychain instead
        let newExtraSwipes = Int(KeychainHelper.get(forKey: "extraSwipes") ?? "0") ?? 0
        if newExtraSwipes != extraSwipes {
            extraSwipes = newExtraSwipes
        }
        
        let newSwipeCount = Int(KeychainHelper.get(forKey: "swipeCount") ?? "0") ?? 0
        if newSwipeCount != swipeCount {
            swipeCount = newSwipeCount
        }
        
        let newTotalLifetimeSwipes = Int(KeychainHelper.get(forKey: "totalLifetimeSwipes") ?? "0") ?? 0
        if newTotalLifetimeSwipes != totalLifetimeSwipes {
            totalLifetimeSwipes = newTotalLifetimeSwipes
        }
        
        NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
    }
    
    // MARK: - Daily Reset Using Keychain
    private func setupDailyResetTimer() {
        // Check for reset every hour
        dailyResetTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.resetIfNeeded()
        }
    }
    
    func resetIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        
        let lastResetString = KeychainHelper.get(forKey: "lastSwipeResetDate")
        let lastResetDate = lastResetString.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .distantPast
        
        if !Calendar.current.isDate(today, inSameDayAs: lastResetDate) {
            // Reset count but preserve extra swipes and lifetime total
            swipeCount = 0
            
            // Update reset date
            let todayString = ISO8601DateFormatter().string(from: today)
            KeychainHelper.save(todayString, forKey: "lastSwipeResetDate")
            
            
            // Force UI update
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
            }
        }
    }
    
    // MARK: - Remaining Swipes
    func remainingSwipes() -> Int {
        if isPremium {
            return .max
        }
        
        let freeRemaining = max(0, 100 - swipeCount)
        let total = freeRemaining + extraSwipes
        
        return total
    }
    
    // MARK: - Can User Swipe Check
    func canUserSwipe() -> Bool {
        if isPremium {
            return true
        }
        
        return remainingSwipes() > 0
    }
    
    // MARK: - Optional: Track if Free Swipes Ever Used
    var hasUsedFreeSwipes: Bool {
        return KeychainHelper.get(forKey: "hasUsedFreeSwipes") == "true"
    }
    
    private func markSwipesUsed() {
        KeychainHelper.save("true", forKey: "hasUsedFreeSwipes")
    }
    
    // MARK: - Debug Information
    func debugInfo() -> String {
        return """
        Premium: \(isPremium)
        Daily Swipe Count: \(swipeCount)/100
        Total Lifetime Swipes: \(totalLifetimeSwipes)
        Extra Swipes: \(extraSwipes)
        Remaining: \(remainingSwipes())
        Can Swipe: \(canUserSwipe())
        Storage: Keychain (persistent across app deletions)
        """
    }
    
    // MARK: - Admin/Debug Functions
    #if DEBUG
    func clearAllData() {
        KeychainHelper.save("", forKey: "swipeCount")
        KeychainHelper.save("", forKey: "totalLifetimeSwipes")
        KeychainHelper.save("", forKey: "extraSwipes")
        KeychainHelper.save("", forKey: "lastSwipeResetDate")
        KeychainHelper.save("", forKey: "hasUsedFreeSwipes")

        swipeCount = 0
        totalLifetimeSwipes = 0
        extraSwipes = 0

    }
    #endif
}

// MARK: - Notification for UI Updates
extension Notification.Name {
    static let swipeCountChanged = Notification.Name("swipeCountChanged")
}
