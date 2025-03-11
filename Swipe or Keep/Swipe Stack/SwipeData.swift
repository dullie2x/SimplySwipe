import Foundation

class SwipeData: ObservableObject {
    @Published var swipeCount: Int {
        didSet {
            UserDefaults.standard.set(swipeCount, forKey: "swipeCount")
        }
    }

    // Singleton instance
    static let shared: SwipeData = SwipeData()

    private init() {
        self.swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
    }

    func incrementSwipeCount() {
        swipeCount += 1
    }
}
