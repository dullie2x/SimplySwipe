import SwiftUI
import SafariServices

struct SettingsView: View {
    @State private var showingResetConfirmation = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfUse = false
    @State private var isResetting = false // Add loading state
    #if DEBUG
    @State private var showingNewUserResetConfirmation = false
    #endif
    
    private let privacyPolicyURL = URL(string: "https://www.ariestates.com/simply-swipe")!
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.custom(AppFont.regular, size: 34))
                    .foregroundColor(.white)
                    .padding(.top, 12)

                // Reset Swiping Progress
                Button(action: {
                    showingResetConfirmation = true
                }) {
                    statActionCard(
                        icon: "arrow.counterclockwise",
                        title: "Reset Swiping Progress",
                        isLoading: isResetting
                    )
                }
                .disabled(isResetting)
                
                // Privacy Policy
                Button(action: {
                    showingPrivacyPolicy = true
                }) {
                    statActionCard(icon: "lock.shield", title: "Privacy Policy")
                }
                
                // Terms of Use
                Button(action: {
                    showingTermsOfUse = true
                }) {
                    statActionCard(icon: "doc.text", title: "Terms of Use")
                }
                
                // Debug buttons - only visible in debug builds
                #if DEBUG
                VStack(spacing: 12) {
                    Button("Reset Swiping Progress (Debug)") {
                        SwipedMediaManager.shared.resetAllSwipedMedia()
                    }
                    .foregroundColor(.orange)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)

                    Button("Clear Daily Swipe Limits (Debug)") {
                        SwipeData.shared.clearAllData()
                    }
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)

                    Button("🔴 Reset to New User (Debug)") {
                        showingNewUserResetConfirmation = true
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                .confirmationDialog(
                    "Reset to New User?",
                    isPresented: $showingNewUserResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Reset Everything", role: .destructive) {
                        resetToNewUser()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will wipe all swipe history, daily limits, onboarding, tooltips, and app rating state — exactly like a fresh install.")
                }
                #endif
                
                Spacer()
            }
            .padding(.bottom, 25)
            .background(Color.black.edgesIgnoringSafeArea(.all))
        }
        .confirmationDialog(
            "Reset Swiping Progress",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Progress", role: .destructive) {
                resetAllProgress()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will make ALL items unreviewed again - everything goes back to the main queue as if you never swiped anything. Items in trash will be cleared. Your daily swipe limits will be preserved. This action cannot be undone.")
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            SafariView(url: privacyPolicyURL)
        }
        .sheet(isPresented: $showingTermsOfUse) {
            SafariView(url: termsOfUseURL)
        }
    }

    private func statActionCard(icon: String, title: String, isLoading: Bool = false) -> some View {
        HStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
                    .frame(width: 40)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 40)
            }

            Text(title)
                .font(.custom(AppFont.regular, size: 18))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(isLoading ? 0.1 : 0.15))
        )
        .padding(.horizontal, 16)
    }

    private func resetAllProgress() {
        isResetting = true
        
        // Reset the data first
        SwipedMediaManager.shared.resetAllSwipedMedia()
        
        // Force ProgressManager to invalidate and recalculate all progress
        Task {
            // Invalidate all caches in ProgressManager
            await ProgressManager.shared.invalidateCache()
            
            // Manually trigger recalculation by fetching fresh progress
            let categoryResults = await ProgressManager.shared.getCategoryProgress()
            let yearResults = await ProgressManager.shared.getYearProgress(for: MediaDataManager.shared.yearsList)
            let albumResults = await ProgressManager.shared.getAlbumProgress(for: MediaDataManager.shared.folders)
            
            // Update MediaDataManager's published properties on main actor
            await MainActor.run {
                MediaDataManager.shared.categoryProgress = categoryResults
                MediaDataManager.shared.yearProgress = yearResults
                MediaDataManager.shared.albumProgress = albumResults
                
                // Post notifications after refresh is complete
                NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
                NotificationCenter.default.post(name: NSNotification.Name("ProgressDidReset"), object: nil)
                
                // Re-enable button after refresh
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isResetting = false
                }
            }
        }
        
    }
    
    private func resetUserDefaults() {
        // Reset any UserDefaults keys that might be tracking swiping progress
        let defaults = UserDefaults.standard
        
        // Common keys that might be used for tracking progress
        let keysToReset = [
            "swipedMediaIds",
            "swipingProgress",
            "currentSwipeIndex",
            "processedMediaIds",
            "swipeSession",
            "lastSwipeDate"
        ]
        
        for key in keysToReset {
            defaults.removeObject(forKey: key)
        }
        
        defaults.synchronize()
    }
    
    private func forceRefreshManagers() {
        // Force any ObservableObject managers to refresh their published properties
        DispatchQueue.main.async {
            // Post multiple notifications to ensure all UI components refresh
            NotificationCenter.default.post(name: .swipeCountChanged, object: nil)

            // Post a custom notification for progress updates
            NotificationCenter.default.post(
                name: NSNotification.Name("ProgressDidReset"),
                object: nil
            )
        }
    }

    #if DEBUG
    private func resetToNewUser() {
        let defaults = UserDefaults.standard

        // Swipe history & trash
        SwipedMediaManager.shared.resetAllSwipedMedia()

        // Daily swipe counts & Keychain data
        SwipeData.shared.clearAllData()

        // Onboarding & tooltips
        defaults.removeObject(forKey: "completedWelcomeOnboarding")
        defaults.removeObject(forKey: "seenRandomTooltip")
        defaults.removeObject(forKey: "seenMainTooltip")
        defaults.removeObject(forKey: "seenTrashTooltip")
        defaults.removeObject(forKey: "seenUserTooltip")

        // App rating state
        defaults.removeObject(forKey: "app.rating.prompt.counter")
        defaults.removeObject(forKey: "app.rating.last.prompt.date")
        defaults.removeObject(forKey: "app.has.rated.app")

        // Premium cache
        defaults.removeObject(forKey: "cachedIsPremium")

        // Photo/video counts
        defaults.removeObject(forKey: "photoCount")
        defaults.removeObject(forKey: "videoCount")

        defaults.synchronize()

        // Refresh UI
        NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("ProgressDidReset"), object: nil)
    }
    #endif
}

// Safari View Controller wrapper
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {
        // No update needed
    }
}
