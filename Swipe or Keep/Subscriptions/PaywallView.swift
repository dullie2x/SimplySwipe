import SwiftUI
import SafariServices

struct PaywallView: View {
    @Environment(\.dismiss) var dismiss
    @State private var animate = false
    @State private var showAdView = false
    @State private var showingTermsOfUse = false
    @State private var isRestoring = false
    
    // Add StoreKitManager
    @ObservedObject private var storeManager = StoreKitManager.shared

    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.7), Color.blue.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 20) {
                    // Close Button (Top-Right)
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white.opacity(0.2))
                                .shadow(radius: 5)
                        }
                        .padding(.top, 15)
                        .padding(.trailing, 15)
                    }

                    Spacer(minLength: 10)

                    // Title & Subtitle
                    VStack(spacing: 10) {
                        Text("Unlock Unlimited Swipes")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(radius: 5)

                        Text("Upgrade or watch an ad for 10 more.")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .padding(.top, -20)

                    // Watch Ad Option
                    VStack(spacing: 10) {
                        Button(action: {
                            showAdView = true
                        }) {
                            HStack {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 22))
                                Text("Watch Ad for 10 More Swipes")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.9))
                            .cornerRadius(12)
                            .shadow(radius: 5)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Pricing Options
                    VStack(spacing: 15) {
                        PaywallOption(
                            title: "Unlimited Swipes - Monthly",
                            price: getPriceString(for: .monthly),
                            highlight: false,
                            animate: $animate
                        ) {
                            storeManager.purchase(.monthly)
                        }
                        
                        PaywallOption(
                            title: "Unlimited Swipes - Yearly",
                            price: getPriceString(for: .yearly),
                            highlight: true,
                            animate: $animate
                        ) {
                            storeManager.purchase(.yearly)
                        }
                        
                        PaywallOption(
                            title: "Lifetime Access",
                            price: getPriceString(for: .lifetime),
                            highlight: false,
                            animate: $animate
                        ) {
                            storeManager.purchase(.lifetime)
                        }
                        
                        PaywallOption(
                            title: "200 Extra Swipes",
                            price: getPriceString(for: .extraSwipes),
                            highlight: false,
                            animate: $animate
                        ) {
                            storeManager.purchase(.extraSwipes)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Terms & Restore Purchase
                    VStack(spacing: 5) {
                        Button(action: {
                            isRestoring = true
                            storeManager.restorePurchases()
                            
                            // Add a delay to give feedback to the user
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isRestoring = false
                                
                                // If restored successfully and premium, dismiss
                                if storeManager.isPremium {
                                    dismiss()
                                }
                            }
                        }) {
                            if isRestoring {
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Restoring...")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            } else {
                                Text("Restore Purchase")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        Text("Terms of Use")
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                            .underline()
                            .onTapGesture {
                                showingTermsOfUse = true
                            }
                    }
                    .padding(.top, 40)

                    Spacer(minLength: 40)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            animate.toggle()
            
            // When view appears, check if user is already premium
            Task {
                await storeManager.checkEntitlements()
                
                // If they're premium, we can dismiss the paywall
                if storeManager.isPremium {
                    dismiss()
                }
            }
        }
        .onChange(of: storeManager.isPremium) { newValue in
            // If they become premium during this session, dismiss the paywall
            if newValue {
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showAdView) {
            AdView()
        }
        .sheet(isPresented: $showingTermsOfUse) {
            SafariView(url: termsOfUseURL)
        }
        .interactiveDismissDisabled(true)
    }
    
    // Helper function to get formatted price string
    private func getPriceString(for productID: StoreKitManager.ProductID) -> String {
        if let product = storeManager.products.first(where: { $0.id == productID.rawValue }) {
            return product.displayPrice
        }
        
        // Default prices if product info not loaded yet
        switch productID {
        case .monthly:
            return "$2.99 / Month"
        case .yearly:
            return "$14.99 / Year"
        case .lifetime:
            return "$29.99 One-Time"
        case .extraSwipes:
            return "$0.99 One-Time"
        }
    }
}

// Unified Paywall Option Button
struct PaywallOption: View {
    let title: String
    let price: String
    let highlight: Bool
    @Binding var animate: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.system(size: highlight ? 16 : 18, weight: .bold))
                        .foregroundColor(highlight ? .black : .white)
                    
                    Text(price)
                        .font(.system(size: 18, weight: highlight ? .bold : .regular))
                        .foregroundColor(highlight ? .red : .white.opacity(0.8))
                }
                Spacer()
                
                if highlight {
                    Text("🔥 Save 58%")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .scaleEffect(animate ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: animate)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(highlight ? Color.yellow.opacity(0.9) : Color.white.opacity(0.1))
                    .shadow(color: highlight ? Color.yellow.opacity(0.5) : Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            )
            .scaleEffect(highlight && animate ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.7), value: animate)
        }
        .padding(.vertical, highlight ? 5 : 0)
    }
}


struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView()
    }
}
