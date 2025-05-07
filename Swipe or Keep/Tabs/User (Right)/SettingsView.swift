import SwiftUI
import SafariServices

struct SettingsView: View {
    @State private var showingResetConfirmation = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfUse = false
    
    private let privacyPolicyURL = URL(string: "https://www.ariestates.com/simply-swipe")!
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 12) // Reduced top padding to move it closer to the top

                // Send Feedback
//                Button(action: {
//                    // Add feedback link here
//                }) {
//                    statActionCard(icon: "message.fill", title: "Send Feedback")
//                }

                // Reset Swiping Progress
                Button(action: {
                    showingResetConfirmation = true
                }) {
                    statActionCard(icon: "arrow.counterclockwise", title: "Reset Swiping Progress")
                }
                
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
                
                Spacer()
            }
            .padding(.bottom, 25) // Only keep bottom padding for spacing
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
            Text("This will reset all of your swiping progress. This action cannot be undone.")
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            SafariView(url: privacyPolicyURL)
        }
        .sheet(isPresented: $showingTermsOfUse) {
            SafariView(url: termsOfUseURL)
        }
    }

    private func statActionCard(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.green)
                .frame(width: 40)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
        )
        .padding(.horizontal, 16)
    }

    private func resetAllProgress() {
        SwipedMediaManager.shared.resetAllSwipedMedia()
        UserDefaults.standard.set(0, forKey: "swipeCount")
    }
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
