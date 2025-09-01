import SwiftUI
import GoogleMobileAds
import StoreKit
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
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(AdHelper.shared)
                // ✅ Global SwiftUI font override (affects all Text by default)
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
            let names = UIFont.fontNames(forFamilyName: family).joined(separator: ", ")
            print("🅵 \(family): \(names)")
        }
        #endif

        // Configure audio session to allow background music to continue
        configureInitialAudioSession()

        // Initialize Google Mobile Ads and preload a rewarded ad
        MobileAds.shared.start { status in
            print("📱 Google Mobile Ads SDK initialization status: \(status)")
            self.loadRewardedAd()
        }

        return true
    }

    // MARK: - Audio Session Configuration
    private func configureInitialAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            print("🎵 Audio session configured for video playback but allowing background music")
        } catch {
            print("❌ Failed to configure initial audio session: \(error)")
        }
    }

    // Call this method only when user unmutes a video
    func activateVideoPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
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
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("🎵 Audio session deactivated - background music can resume")
        } catch {
            print("❌ Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - Rewarded Ad
    func loadRewardedAd() {
        // Skip if already loading or an ad is in memory
        if isLoadingAd || rewardedAd != nil {
            print("⚠️ Ad already loading or already loaded, skipping duplicate request")
            return
        }

        isLoadingAd = true
        print("📲 Starting to load rewarded ad")

        let request = Request()

        RewardedAd.load(with: rewardedAdUnitID, request: request) { [weak self] ad, error in
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

    func showRewardedAd(from viewController: UIViewController, completion: (() -> Void)? = nil) {
        self.rewardEarned = false

        // Store optional completion to run after dismissal
        if let completion = completion {
            self.adDismissedHandler = completion
        }

        if let ad = self.rewardedAd {
            print("🎬 Presenting rewarded ad")
            DispatchQueue.main.async {
                ad.present(from: viewController) { [weak self] in
                    guard let self = self else { return }
                    print("🎁 User earned reward!")
                    self.rewardEarned = true

                    // Grant the reward here only
                    let current = UserDefaults.standard.integer(forKey: "extraSwipes")
                    UserDefaults.standard.set(current + 10, forKey: "extraSwipes")

                    // Clear used ad
                    self.rewardedAd = nil
                }
            }
        } else {
            print("⚠️ Rewarded ad not ready")
            self.loadRewardedAd()
            // Still call completion so UI can continue
            DispatchQueue.main.async {
                self.adDismissedHandler?()
                self.adDismissedHandler = nil
            }
        }
    }

    // MARK: - GADFullScreenContentDelegate
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("🏁 Ad dismissed")

        // Reload the rewarded ad if that's what was shown
        if ad is RewardedAd {
            rewardedAd = nil
            loadRewardedAd()
        }

        // Call any waiting completion
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
