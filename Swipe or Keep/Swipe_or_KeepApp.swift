import SwiftUI
import GoogleMobileAds
import StoreKit

@main
struct Swipe_or_KeepApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showSplash = true
    
    init() {
        // Force dark mode throughout the app
        UIView.appearance().overrideUserInterfaceStyle = .dark
    }
    
    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(AdHelper.shared)

        }
    }
}

// MARK: - App Delegate with AdMob Implementation
class AppDelegate: NSObject, UIApplicationDelegate, FullScreenContentDelegate {
    // Rewarded ad
    var rewardedAd: RewardedAd?
//    let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313" // Test ad ID
     let rewardedAdUnitID = "ca-app-pub-3883739672732267/8875385644" // Production ad ID

    // Tracking for ad presentation
    @Published var rewardEarned = false
    var adDismissedHandler: (() -> Void)?
    var isLoadingAd = false // Flag to prevent multiple simultaneous loads

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        MobileAds.shared.start { status in
            print("📱 Google Mobile Ads SDK initialization status: \(status)")
            
            // Preload a rewarded ad after SDK initialization
            self.loadRewardedAd()
        }

        return true
    }
    
    // MARK: - Rewarded Ad
    func loadRewardedAd() {
        // Prevent multiple simultaneous ad loads
        if isLoadingAd {
            print("⚠️ Ad already loading, skipping duplicate request")
            return
        }
        
        isLoadingAd = true
        print("📲 Starting to load rewarded ad")
        
        let request = Request()
        
        RewardedAd.load(with: rewardedAdUnitID,
                          request: request) { [weak self] ad, error in
            guard let self = self else { return }
            
            self.isLoadingAd = false
            
            if let error = error {
                print("❌ Failed to load rewarded ad: \(error.localizedDescription)")
                return
            }
            
            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
            print("✅ Rewarded ad loaded successfully")
        }
    }
    
    // Show rewarded ad with improved handling
    func showRewardedAd(from viewController: UIViewController, completion: (() -> Void)? = nil) {
        self.adDismissedHandler = completion
        self.rewardEarned = false
        
        if let ad = rewardedAd {
            print("🎬 Presenting rewarded ad")
            
            // Present on main thread to avoid potential UI issues
            DispatchQueue.main.async {
                ad.present(from: viewController) { [weak self] in
                    guard let self = self else { return }
                    
                    // User earned reward
                    print("🎁 User earned reward!")
                    self.rewardEarned = true
                    
                    // Add the extra swipes
                    let current = UserDefaults.standard.integer(forKey: "extraSwipes")
                    UserDefaults.standard.set(current + 10, forKey: "extraSwipes")
                }
            }
        } else {
            print("⚠️ Rewarded ad not ready, loading a new one")
            loadRewardedAd()
            
            // Call completion handler with delay to avoid UI glitches
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                completion?()
            }
        }
    }
    
    // MARK: - GADFullScreenContentDelegate
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("🏁 Ad dismissed")
        
        // Reload the rewarded ad
        if ad is RewardedAd {
            rewardedAd = nil
            loadRewardedAd()
        }
        
        // Call the dismissal handler on main thread
        DispatchQueue.main.async {
            self.adDismissedHandler?()
            self.adDismissedHandler = nil
        }
    }
    
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        print("👁️ Ad recorded impression")
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("❌ Ad failed to present with error: \(error.localizedDescription)")
        
        // Call the dismissal handler on main thread
        DispatchQueue.main.async {
            self.adDismissedHandler?()
            self.adDismissedHandler = nil
        }
        
        // Reset the rewarded ad
        if ad is RewardedAd {
            rewardedAd = nil
            loadRewardedAd()
        }
    }
}
