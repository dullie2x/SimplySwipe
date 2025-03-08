import Foundation

class SwipeData: ObservableObject {
    @Published var swipeCount: Int = 0

    // Singleton instance
    static let shared = SwipeData()

    private init() {
        // Load the initial swipe count from UserDefaults
        self.swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
    }

    func incrementSwipeCount() {
        swipeCount += 1
        UserDefaults.standard.set(swipeCount, forKey: "swipeCount")
    }
}
