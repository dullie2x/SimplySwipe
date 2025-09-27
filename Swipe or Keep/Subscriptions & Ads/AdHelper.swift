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

    // FIXED: Better reward tracking and completion handling
    func showRewardedAd(from viewController: UIViewController, completion: @escaping () -> Void) {
        guard let appDelegate = self.appDelegate else {
            print("❌ AdHelper: Could not find AppDelegate (not set)")
            completion()
            return
        }

        // Reset reward status before showing ad
        self.rewardEarned = false
        appDelegate.rewardEarned = false
        
        if appDelegate.rewardedAd != nil {
            print("✅ AdHelper: Showing loaded ad")
            
            // Pass completion to AppDelegate - it will call it after ad dismisses
            appDelegate.showRewardedAd(from: viewController) { [weak self] in
                // Sync reward status from AppDelegate
                self?.rewardEarned = appDelegate.rewardEarned
                
                print("🎯 AdHelper: Ad completed. Reward earned: \(appDelegate.rewardEarned)")
                print("🎯 AdHelper: Local reward status: \(self?.rewardEarned ?? false)")
                
                completion()
            }
        } else {
            print("⚠️ AdHelper: No ad loaded, calling completion without reward")
            completion()
        }
    }

    // IMPROVED: More reliable reward checking with detailed logging
    func wasRewardEarned() -> Bool {
        let appDelegateReward = appDelegate?.rewardEarned ?? false
        let localReward = rewardEarned
        
        print("🔍 AdHelper: Checking reward status - Local: \(localReward), AppDelegate: \(appDelegateReward)")
        
        // Return true if either source indicates reward was earned
        let finalResult = localReward || appDelegateReward
        print("🔍 AdHelper: Final reward result: \(finalResult)")
        
        return finalResult
    }
    
    // HELPER FUNCTION - Reset reward status (useful for debugging)
    func resetRewardStatus() {
        rewardEarned = false
        appDelegate?.rewardEarned = false
        print("🔄 AdHelper: Reset all reward statuses")
    }
}
