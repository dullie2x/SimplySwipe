import SwiftUI
import GoogleMobileAds
import StoreKit
import AVFoundation

@main
struct Swipe_or_KeepApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showSplash = true

    init() {
        // Force dark mode
        UIView.appearance().overrideUserInterfaceStyle = .dark

        // 🔐 Set the reference here
        AdHelper.shared.appDelegate = appDelegate
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
        
        // Configure audio session to allow background music to continue
        configureInitialAudioSession()
        
        MobileAds.shared.start { status in
            print("📱 Google Mobile Ads SDK initialization status: \(status)")
            
            // Preload a rewarded ad after SDK initialization
            self.loadRewardedAd()
        }

        return true
    }
    
    // MARK: - Audio Session Configuration
    private func configureInitialAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Set category to playback but don't activate yet - allows background music to continue
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            
            // Don't activate the session yet - this allows background music to continue
            print("🎵 Audio session configured for video playback but allowing background music")
            
        } catch {
            print("❌ Failed to configure initial audio session: \(error)")
        }
    }
    
    // Call this method only when user unmutes a video
    func activateVideoPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Activate the session - this will stop background music
            try audioSession.setActive(true)
            
            print("🎬 Audio session activated - background music stopped")
            
        } catch {
            print("❌ Failed to activate audio session: \(error)")
        }
    }
    
    // Call this method when video is muted
    func allowBackgroundMusic() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Deactivate to allow background music to resume
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            print("🎵 Audio session deactivated - background music can resume")
            
        } catch {
            print("❌ Failed to deactivate audio session: \(error)")
        }
    }
    
    // MARK: - Rewarded Ad
    // UPDATED FUNCTION
    func loadRewardedAd() {
        // Prevent multiple simultaneous ad loads or loading when an ad is already available
        if isLoadingAd || rewardedAd != nil {
            print("⚠️ Ad already loading or already loaded, skipping duplicate request")
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

    // UPDATED FUNCTION
    func showRewardedAd(from viewController: UIViewController, completion: (() -> Void)? = nil) {
        self.rewardEarned = false
        
        // Store the completion handler if provided
        if let completion = completion {
            self.adDismissedHandler = completion
        }

        if let ad = self.rewardedAd {
            print("🎬 Presenting rewarded ad")
            
            // Present on main thread
            DispatchQueue.main.async {
                ad.present(from: viewController) { [weak self] in
                    guard let self = self else { return }
                    print("🎁 User earned reward!")
                    self.rewardEarned = true
                    
                    // Grant the reward here only
                    let current = UserDefaults.standard.integer(forKey: "extraSwipes")
                    UserDefaults.standard.set(current + 10, forKey: "extraSwipes")
                    
                    // Set ad to nil after use to prevent reuse
                    self.rewardedAd = nil
                }
            }
        } else {
            print("⚠️ Rewarded ad not ready")
            self.loadRewardedAd()
            // Call the completion handler
            DispatchQueue.main.async {
                self.adDismissedHandler?()
                self.adDismissedHandler = nil
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
