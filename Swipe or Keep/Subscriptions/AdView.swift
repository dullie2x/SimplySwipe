import SwiftUI
import GoogleMobileAds
import UIKit

struct AdView: View {
    // Environment
    @Environment(\.dismiss) var dismiss
    
    // States
    @State private var adState: AdState = .initializing
    @State private var loadingSeconds = 0
    @State private var timer: Timer? = nil
    @State private var showCloseButton = false
    
    // Access AppDelegate
    private let appDelegate = UIApplication.shared.delegate as? AppDelegate
    
    // MARK: - View Body
    var body: some View {
        ZStack {
            // Full screen semi-transparent background
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            
            // Main content
            VStack(spacing: 20) {
                // Different UI based on ad state
                switch adState {
                case .initializing, .loading:
                    loadingView
                    
                case .displaying:
                    // When ad is displaying, we show minimal UI
                    // The actual ad is displayed by UIKit over this view
                    Text("Ad in progress...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .padding()
                    
                case .error:
                    errorView
                    
                case .complete:
                    completedView
                }
            }
            .padding()
            .frame(maxWidth: 320)
            .background(Color(UIColor.systemGray6).opacity(0.9))
            .cornerRadius(16)
            .shadow(radius: 15)
            
            // Close button overlay
            if showCloseButton {
                VStack {
                    HStack {
                        Spacer()
                        closeButton
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                    Spacer()
                }
            }
        }
        .onAppear {
            startAdSequence()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .interactiveDismissDisabled(true)
    }
    
    // MARK: - Component Views
    
    // Loading view with progress indicator
    private var loadingView: some View {
        VStack(spacing: 12) {
            // Header
            Text("Loading Reward Ad")
                .font(.headline)
                .foregroundColor(.white)
            
            // Progress indicator
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
                .padding(.vertical, 10)
            
            // Status with timer
            Text("\(loadingSeconds)s elapsed...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(height: 150)
    }
    
    // Error view when ad fails to load
    private var errorView: some View {
        VStack(spacing: 15) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(.yellow)
            
            Text("Unable to load advertisement")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Don't worry, you'll still receive your reward!")
                .font(.subheadline)
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            
            Button(action: grantRewardAndDismiss) {
                Text("Continue")
                    .fontWeight(.medium)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(10)
            }
        }
        .frame(height: 200)
    }
    
    // Completed view after ad finishes
    private var completedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundColor(.green)
            
            Text("Reward Earned!")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("You've received 10 extra swipes")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            
            Button(action: { dismiss() }) {
                Text("Continue")
                    .fontWeight(.medium)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(10)
            }
            .padding(.top, 10)
        }
        .frame(height: 200)
    }
    
    // Close button that appears after ad is shown or on error
    private var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
                .shadow(radius: 2)
        }
        .transition(.opacity)
        .buttonStyle(BorderlessButtonStyle())
    }
    
    // MARK: - Ad Management Functions
    
    // Start the ad sequence
    private func startAdSequence() {
        print("📱 AdView: Starting ad sequence")
        adState = .loading
        
        // Start timer to track loading time and handle timeouts
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            loadingSeconds += 1
            
            // Timeout after 15 seconds of loading
            if loadingSeconds >= 15 && adState == .loading {
                print("⏱️ AdView: Ad loading timed out after \(loadingSeconds) seconds")
                handleAdError()
            }
        }
        
        // Try to show ad immediately if already loaded
        if appDelegate?.rewardedAd != nil {
            print("✅ AdView: Ad already loaded, showing immediately")
            showRewardedAd()
        } else {
            print("⏳ AdView: No preloaded ad found, loading now")
            // Load a new ad
            appDelegate?.loadRewardedAd()
            checkAdLoadStatus()
        }
    }
    
    // Periodically check if ad has loaded
    private func checkAdLoadStatus() {
        // Check again in 1 second if we're still in loading state
        guard adState == .loading else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if appDelegate?.rewardedAd != nil {
                print("✅ AdView: Ad finished loading, showing now")
                showRewardedAd()
            } else if loadingSeconds < 14 {
                print("⏳ AdView: Still waiting for ad... (\(loadingSeconds)s)")
                checkAdLoadStatus()
            }
        }
    }
    
    // Actually show the rewarded ad
    private func showRewardedAd() {
        guard let appDelegate = appDelegate, appDelegate.rewardedAd != nil else {
            print("❌ AdView: Failed to show ad - ad is nil")
            handleAdError()
            return
        }
        
        // Find the root view controller
        guard let rootVC = findRootViewController() else {
            print("❌ AdView: Failed to find root view controller")
            handleAdError()
            return
        }
        
        // Update UI state
        adState = .displaying
        
        // Show the ad
        print("🎬 AdView: Presenting ad")
        appDelegate.showRewardedAd(from: rootVC) {
            print("🏁 AdView: Ad dismissed callback received")
            
            // Use main thread for UI updates
            DispatchQueue.main.async {
                self.timer?.invalidate()
                
                // Show close button in any case
                withAnimation {
                    self.showCloseButton = true
                }
                
                if appDelegate.rewardEarned {
                    print("🎁 AdView: Reward earned")
                    self.adState = .complete
                } else {
                    print("⚠️ AdView: Ad shown but no reward signal received")
                    // Grant reward anyway to prevent poor user experience
                    self.grantRewardAndDismiss()
                }
            }
        }
    }
    
    // Helper to find the root view controller
    private func findRootViewController() -> UIViewController? {
        // Try connected scenes approach first
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let rootVC = window.rootViewController {
            return getTopViewController(rootVC)
        }
        
        // Fallback to older method if needed
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return nil
        }
        
        return getTopViewController(rootVC)
    }
    
    // Get the topmost view controller
    private func getTopViewController(_ viewController: UIViewController) -> UIViewController {
        if let presentedVC = viewController.presentedViewController {
            return getTopViewController(presentedVC)
        }
        
        if let navVC = viewController as? UINavigationController {
            if let topVC = navVC.topViewController {
                return getTopViewController(topVC)
            }
        }
        
        if let tabVC = viewController as? UITabBarController {
            if let selectedVC = tabVC.selectedViewController {
                return getTopViewController(selectedVC)
            }
        }
        
        return viewController
    }
    
    // Handle ad loading error
    private func handleAdError() {
        print("⚠️ AdView: Handling ad error")
        adState = .error
        // Show close button
        withAnimation {
            showCloseButton = true
        }
    }
    
    // Grant reward and dismiss
    private func grantRewardAndDismiss() {
        print("🎁 AdView: Granting reward manually")
        
        // Use SwipeData to manage extra swipes instead of directly modifying UserDefaults
        SwipeData.shared.addExtraSwipes(10)
        
        adState = .complete
    }
}

// MARK: - Supporting Types

// Ad states for more readable state management
enum AdState {
    case initializing
    case loading
    case displaying
    case error
    case complete
}

// MARK: - Preview Provider

struct AdView_Previews: PreviewProvider {
    static var previews: some View {
        AdView()
    }
}
