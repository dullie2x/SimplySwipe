import Foundation
import Combine

class SwipeData: ObservableObject {
    @Published var swipeCount: Int {
        didSet {
            UserDefaults.standard.set(swipeCount, forKey: "swipeCount")
        }
    }

    @Published var isPremium: Bool = false
    private var cancellables = Set<AnyCancellable>()

    static let shared: SwipeData = SwipeData()

    private init() {
        self.swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
        self.isPremium = StoreKitManager.shared.isPremium

        // Observe premium status
        StoreKitManager.shared.$isPremium
            .receive(on: RunLoop.main)
            .assign(to: \.isPremium, on: self)
            .store(in: &cancellables)

        resetIfNeeded()
    }

    func incrementSwipeCount() {
        if isPremium {
            return // Unlimited swipes
        }

        // Use extra swipes first
        if swipeCount >= 50 {
            var extra = UserDefaults.standard.integer(forKey: "extraSwipes")
            if extra > 0 {
                extra -= 1
                UserDefaults.standard.set(extra, forKey: "extraSwipes")
                print("Used 1 extra swipe. Remaining: \(extra)")
                return
            }
        }

        swipeCount += 1
    }

    func resetIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastResetDate = UserDefaults.standard.object(forKey: "lastSwipeResetDate") as? Date ?? .distantPast

        if !Calendar.current.isDate(today, inSameDayAs: lastResetDate) {
            swipeCount = 0
            UserDefaults.standard.set(today, forKey: "lastSwipeResetDate")
            print("Swipe count reset for new day.")
        }
    }

    func remainingSwipes() -> Int {
        if isPremium { return .max }

        let base = max(0, 50 - swipeCount)
        let extras = UserDefaults.standard.integer(forKey: "extraSwipes")
        return base + extras
    }
}
