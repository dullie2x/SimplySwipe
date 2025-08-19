import SwiftUI
import UIKit
import GoogleMobileAds

// Singleton class to help with ad presentation from anywhere in the app
class AdHelper: ObservableObject {
    static let shared = AdHelper()
    
    @Published var rewardEarned = false
    var appDelegate: AppDelegate?

    private init() {}

    func getRewardedAdView() -> some View {
        return AdView()
            .environmentObject(self)
    }

    func isRewardedAdReady() -> Bool {
        return appDelegate?.rewardedAd != nil
    }

    func preloadRewardedAd() {
        guard let appDelegate = self.appDelegate else {
            print("❌ AdHelper: No AppDelegate available for preload")
            return
        }
        if appDelegate.rewardedAd == nil && !appDelegate.isLoadingAd {
            appDelegate.loadRewardedAd()
        }
    }

    // UPDATED FUNCTION
    func showRewardedAd(from viewController: UIViewController, completion: @escaping () -> Void) {
        guard let appDelegate = self.appDelegate else {
            print("❌ AdHelper: Could not find AppDelegate (not set)")
            completion()
            return
        }

        self.rewardEarned = false
        
        if appDelegate.rewardedAd != nil {
            print("✅ AdHelper: Showing loaded ad")
            // Add a wrapper completion handler that will update rewardEarned
            appDelegate.showRewardedAd(from: viewController) {
                // Make sure to sync the reward status before calling completion
                self.rewardEarned = appDelegate.rewardEarned
                completion()
            }
        } else {
            print("⚠️ AdHelper: No ad loaded, calling completion")
            completion()
        }
    }

    // UPDATED FUNCTION
    func wasRewardEarned() -> Bool {
        // First check our own record, then check AppDelegate's record
        return rewardEarned || (appDelegate?.rewardEarned ?? false)
    }
}
