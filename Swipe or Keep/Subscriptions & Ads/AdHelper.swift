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
            return
        }
        if appDelegate.rewardedAd == nil && !appDelegate.isLoadingAd {
            appDelegate.loadRewardedAd()
        }
    }

    // FIXED: Better reward tracking and completion handling
    func showRewardedAd(from viewController: UIViewController, completion: @escaping () -> Void) {
        guard let appDelegate = self.appDelegate else {
            completion()
            return
        }

        // Reset reward status before showing ad
        self.rewardEarned = false
        appDelegate.rewardEarned = false
        
        if appDelegate.rewardedAd != nil {
            
            // Pass completion to AppDelegate - it will call it after ad dismisses
            appDelegate.showRewardedAd(from: viewController) { [weak self] in
                // Sync reward status from AppDelegate
                self?.rewardEarned = appDelegate.rewardEarned
                
                
                completion()
            }
        } else {
            completion()
        }
    }

    // IMPROVED: More reliable reward checking with detailed logging
    func wasRewardEarned() -> Bool {
        let appDelegateReward = appDelegate?.rewardEarned ?? false
        let localReward = rewardEarned
        
        
        // Return true if either source indicates reward was earned
        let finalResult = localReward || appDelegateReward
        
        return finalResult
    }
    
    // HELPER FUNCTION - Reset reward status (useful for debugging)
    func resetRewardStatus() {
        rewardEarned = false
        appDelegate?.rewardEarned = false
    }
}
