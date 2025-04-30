import SwiftUI
import UIKit
import GoogleMobileAds

// Singleton class to help with ad presentation from anywhere in the app
class AdHelper: ObservableObject {
    static let shared = AdHelper()
    
    // Published property to track reward state
    @Published var rewardEarned = false
    
    private init() {
        // Private initializer for singleton
    }
    
    // MARK: - Show Rewarded Ad
    
    // Get the rewarded ad view for presentation
    func getRewardedAdView() -> some View {
        return AdView()
            .environmentObject(self)
    }
    
    // Check if rewarded ad is loaded
    func isRewardedAdReady() -> Bool {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return false
        }
        
        return appDelegate.rewardedAd != nil
    }
    
    // Preload rewarded ad in advance
    func preloadRewardedAd() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        
        if appDelegate.rewardedAd == nil {
            appDelegate.loadRewardedAd()
        }
    }
    
    // Show rewarded ad from a view controller
    func showRewardedAd(from viewController: UIViewController, completion: @escaping () -> Void) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            print("❌ AdHelper: No AppDelegate available")
            completion()
            return
        }
        
        self.rewardEarned = false
        
        if appDelegate.rewardedAd != nil {
            appDelegate.showRewardedAd(from: viewController) { [weak self] in
                self?.rewardEarned = appDelegate.rewardEarned
                completion()
            }
        } else {
            print("⚠️ AdHelper: No ad loaded, can't show")
            appDelegate.loadRewardedAd()
            completion()
        }
    }
    
    // Check if reward was earned
    func wasRewardEarned() -> Bool {
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            return rewardEarned || appDelegate.rewardEarned
        }
        return rewardEarned
    }
}

// Extension to show rewarded ads from various places in the app
extension View {
    // Show rewarded ad with a binding to control presentation
    func showRewardedAd(isPresented: Binding<Bool>) -> some View {
        return self.fullScreenCover(isPresented: isPresented) {
            AdView()
                .environmentObject(AdHelper.shared)
        }
    }
    
    // Preload rewarded ad on appear
    func preloadRewardedAd() -> some View {
        return self.onAppear {
            AdHelper.shared.preloadRewardedAd()
        }
    }
}
