import Foundation
import Combine


// MARK: - SwipeData Singleton
class SwipeData: ObservableObject {
    @Published var swipeCount: Int {
        didSet {
            UserDefaults.standard.set(swipeCount, forKey: "swipeCount")
            NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
        }
    }

    @Published var extraSwipes: Int {
        didSet {
            UserDefaults.standard.set(extraSwipes, forKey: "extraSwipes")
            NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
        }
    }

    @Published var isPremium: Bool = false
    private var cancellables = Set<AnyCancellable>()

    static let shared = SwipeData()

    private init() {
        self.swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
        self.extraSwipes = UserDefaults.standard.integer(forKey: "extraSwipes")
        self.isPremium = StoreKitManager.shared.isPremium

        StoreKitManager.shared.$isPremium
            .receive(on: RunLoop.main)
            .assign(to: \.isPremium, on: self)
            .store(in: &cancellables)

        resetIfNeeded()
    }

    // MARK: - Swipe Handling
    func incrementSwipeCount() {
        if !isPremium && swipeCount >= 100 {
            if extraSwipes > 0 {
                extraSwipes -= 1
                print("Used 1 extra swipe. Remaining: \(extraSwipes)")
            }
        }

        swipeCount += 1

        if swipeCount > 0 {
            markSwipesUsed()
        }
    }

    func addExtraSwipes(_ count: Int) {
        extraSwipes += count
    }

    func refreshFromUserDefaults() {
        let newExtraSwipes = UserDefaults.standard.integer(forKey: "extraSwipes")
        if newExtraSwipes != extraSwipes {
            extraSwipes = newExtraSwipes
        }

        let newSwipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
        if newSwipeCount != swipeCount {
            swipeCount = newSwipeCount
        }

        NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
    }

    // MARK: - Daily Reset Using Keychain
    func resetIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())

        let lastResetString = KeychainHelper.get(forKey: "lastSwipeResetDate")
        let lastResetDate = lastResetString.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .distantPast

        if !Calendar.current.isDate(today, inSameDayAs: lastResetDate) {
            swipeCount = 0
            let todayString = ISO8601DateFormatter().string(from: today)
            KeychainHelper.save(todayString, forKey: "lastSwipeResetDate")
            print("Swipe count reset for new day.")
        }
    }

    // MARK: - Remaining Swipes
    func remainingSwipes() -> Int {
        if isPremium { return .max }

        let base = max(0, 100 - swipeCount)
        return base + extraSwipes
    }

    // MARK: - Optional: Track if Free Swipes Ever Used
    var hasUsedFreeSwipes: Bool {
        return KeychainHelper.get(forKey: "hasUsedFreeSwipes") == "true"
    }

    func markSwipesUsed() {
        KeychainHelper.save("true", forKey: "hasUsedFreeSwipes")
    }
}

// MARK: - Notification for UI Updates
extension Notification.Name {
    static let swipeCountChanged = Notification.Name("swipeCountChanged")
}
