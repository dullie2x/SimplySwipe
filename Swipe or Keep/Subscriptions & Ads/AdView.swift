import SwiftUI
import GoogleMobileAds
import UIKit

struct AdView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var adHelper: AdHelper
    
    @State private var adState: AdState = .initializing
    @State private var showCloseButton = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                switch adState {
                case .initializing, .loading:
                    loadingView
                case .displaying:
                    displayingView
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
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            Text("Loading Reward Ad")
                .font(.headline)
                .foregroundColor(.white)
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
                .padding(.vertical, 10)
        }
        .frame(height: 150)
    }
    
    private var displayingView: some View {
        VStack(spacing: 12) {
            Text("Ad in progress...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .padding()
        }
    }
    
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
    
    // UPDATED FUNCTION
    private func startAdSequence() {
        print("📱 AdView: Starting ad sequence")
        adState = .loading
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let rootVC = findRootViewController() else {
                print("❌ AdView: No root view controller")
                handleAdError()
                return
            }
            
            print("🎬 AdView: Attempting to present ad from \(type(of: rootVC))")
            
            // Important: Set to displaying BEFORE showing the ad
            adState = .displaying
            
            // Show the ad with a completion handler
            adHelper.showRewardedAd(from: rootVC) {
                DispatchQueue.main.async {
                    print("🏁 Ad finished / dismissed")
                    
                    // Check reward status and set state
                    if adHelper.wasRewardEarned() {
                        print("✅ Reward was earned, showing completed view")
                        adState = .complete
                    } else {
                        print("⚠️ No reward earned, showing error view")
                        adState = .error
                    }
                    
                    // Always show close button after ad completes
                    withAnimation {
                        showCloseButton = true
                    }
                }
            }
        }
    }
    
    private func findRootViewController() -> UIViewController? {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let rootVC = window.rootViewController {
            return getTopViewController(rootVC)
        }
        return nil
    }
    
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
    
    private func handleAdError() {
        print("⚠️ AdView: Handling ad error")
        adState = .error
        
        withAnimation {
            showCloseButton = true
        }
    }
    
    private func grantRewardAndDismiss() {
        print("🎁 AdView: Granting reward manually")
        SwipeData.shared.addExtraSwipes(10)
        adState = .complete
    }
}

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
