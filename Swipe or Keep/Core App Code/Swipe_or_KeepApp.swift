import SwiftUI
import GoogleMobileAds
import AVFoundation

// MARK: - App Font
enum AppFont {
    static let regular = "Poppins-Bold"

    // SwiftUI global font that respects Dynamic Type
    static func swiftUIFont(for textStyle: UIFont.TextStyle) -> Font {
        let size = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        return .custom(AppFont.regular, size: size)
    }

    // UIKit helper
    static func uiFont(_ size: CGFloat) -> UIFont {
        UIFont(name: AppFont.regular, size: size) ?? .systemFont(ofSize: size)
    }
}

@main
struct Swipe_or_KeepApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showSplash = true

    init() {
        // Force dark mode globally
        UIView.appearance().overrideUserInterfaceStyle = .dark

        // Global UIKit text appearances (common items)
        UINavigationBar.appearance().titleTextAttributes = [
            .font: AppFont.uiFont(20)
        ]
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: AppFont.uiFont(34)
        ]
        UITabBarItem.appearance().setTitleTextAttributes(
            [.font: AppFont.uiFont(12)],
            for: .normal
        )

        // Pass delegate reference used elsewhere in your app
        AdHelper.shared.appDelegate = appDelegate
        
        // Get new random quote on app launch
        QuotesManager.shared.selectRandomQuote()
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(AdHelper.shared)
                // Global SwiftUI font override (affects all Text by default)
                .environment(\.font, AppFont.swiftUIFont(for: .body))
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
    var isLoadingAd = false // Prevent multiple simultaneous loads

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // (Optional) Dump fonts once in DEBUG to confirm PostScript names
        #if DEBUG
        for family in UIFont.familyNames.sorted() {
            _ = UIFont.fontNames(forFamilyName: family)
        }
        #endif

        // Configure audio session to allow background music to continue
        configureInitialAudioSession()

        // Initialize Google Mobile Ads and preload a rewarded ad
        MobileAds.shared.start { status in
            self.loadRewardedAd()
        }

        return true
    }

    // MARK: - Audio Session Configuration
    private func configureInitialAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // Call this method only when user unmutes a video
    func activateVideoPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
        } catch {
            print("Failed to activate video playback: \(error.localizedDescription)")
        }
    }

    // Call this method when video is muted
    func allowBackgroundMusic() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to allow background music: \(error.localizedDescription)")
        }
    }

    // MARK: - Rewarded Ad
    func loadRewardedAd() {
        // Skip if already loading or an ad is in memory
        if isLoadingAd || rewardedAd != nil {
            return
        }

        isLoadingAd = true

        let request = Request()

        RewardedAd.load(with: rewardedAdUnitID, request: request) { [weak self] ad, error in
            guard let self = self else { return }
            self.isLoadingAd = false

            if error != nil {
                return
            }

            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
        }
    }

    // CRITICAL FIX: Don't call completion immediately - store it to call later
    func showRewardedAd(from viewController: UIViewController, completion: (() -> Void)? = nil) {
        // Reset reward status
        self.rewardEarned = false

        // IMPORTANT: Store completion to call after ad dismisses, not now
        self.adDismissedHandler = completion

        if let ad = self.rewardedAd {
            DispatchQueue.main.async {
                ad.present(from: viewController) { [weak self] in
                    guard let self = self else { return }
                    self.rewardEarned = true

                    // DON'T call completion here - it will be called when ad dismisses
                    // Clear used ad
                    self.rewardedAd = nil
                }
            }
        } else {
            self.loadRewardedAd()
            // Only call completion immediately if there's no ad to show
            DispatchQueue.main.async {
                self.adDismissedHandler?()
                self.adDismissedHandler = nil
            }
        }
    }

    // MARK: - GADFullScreenContentDelegate

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {

        // IMPORTANT: Call completion FIRST while reward status is still valid
        DispatchQueue.main.async {
            self.adDismissedHandler?()
            self.adDismissedHandler = nil
            
            // THEN reset reward status and reload ad
            self.rewardEarned = false  // Reset AFTER completion handler runs
        }

        // Reload the rewarded ad if that's what was shown
        if ad is RewardedAd {
            rewardedAd = nil
            loadRewardedAd()
        }
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {

        // Resume UI flows
        DispatchQueue.main.async {
            self.adDismissedHandler?()
            self.adDismissedHandler = nil
        }

        // Reset and try to load again
        if ad is RewardedAd {
            rewardedAd = nil
            loadRewardedAd()
        }
    }
}
