import SwiftUI
import StoreKit

class AppRatingManager: ObservableObject {
    static let shared = AppRatingManager()

    private let userDefaults = UserDefaults.standard
    private let ratingThreshold = 1
    private let ratingPromptCounterKey = "app.rating.prompt.counter"
    private let lastRatingPromptDateKey = "app.rating.last.prompt.date"
    private let hasRatedAppKey = "app.has.rated.app"
    private let minDaysBetweenPrompts = 14

    // MARK: - Public Methods

    func registerUserAction() {
        if userDefaults.bool(forKey: hasRatedAppKey) { return }

        let currentCount = userDefaults.integer(forKey: ratingPromptCounterKey)
        userDefaults.set(currentCount + 1, forKey: ratingPromptCounterKey)
    }

    func shouldPromptForRating() -> Bool {
        if userDefaults.bool(forKey: hasRatedAppKey) {
            return false
        }

        if let lastPromptDate = userDefaults.object(forKey: lastRatingPromptDateKey) as? Date {
            let days = Calendar.current.dateComponents([.day], from: lastPromptDate, to: Date()).day ?? 0
            if days < minDaysBetweenPrompts { return false }
        }

        return userDefaults.integer(forKey: ratingPromptCounterKey) >= ratingThreshold
    }

    func didPromptForRating() {
        userDefaults.set(0, forKey: ratingPromptCounterKey)
        userDefaults.set(Date(), forKey: lastRatingPromptDateKey)
    }

    func markAsRated() {
        userDefaults.set(true, forKey: hasRatedAppKey)
    }

    /// Call this in your SwiftUI view to trigger the full review flow
    func showRatingFlow(from viewController: UIViewController) {
        guard shouldPromptForRating() else { return }

        let alert = UIAlertController(title: "Enjoying Simply Swipe?",
                                  message: "Would you mind leaving us a quick review?",
                                  preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { _ in
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: scene)
                self.didPromptForRating()
                self.markAsRated()
            }
        }))

        alert.addAction(UIAlertAction(title: "Not Really", style: .default, handler: { _ in
            if let url = URL(string: "https://forms.gle/f7EyjVj4S5x2yGi27") {
                UIApplication.shared.open(url)
                self.didPromptForRating()
            }
        }))

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        viewController.present(alert, animated: true)
    }
}
