import SwiftUI
import SafariServices

struct PaywallMaxView: View {
    @Environment(\.dismiss) var dismiss
    @State private var animate = false
    @State private var showAdView = false
    @State private var showingTermsOfUse = false
    @State private var showingPrivacyPolicy = false
    @State private var isRestoring = false
    
    @ObservedObject private var storeManager = StoreKitManager.shared
    
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let privacyPolicyURL = URL(string: "https://www.ariestates.com/simply-swipe")!

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.red.opacity(0.7), Color.orange.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
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
                    
                    VStack(spacing: 10) {
                        Text("Out of Swipes!")
                            .font(.custom(AppFont.regular, size: 30))
                            .foregroundColor(.white)
                            .shadow(radius: 5)

                    }

                    Button(action: {
                        showAdView = true
                    }) {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 22))
                            Text("Watch Ad for 10 More Swipes")
                                .font(.custom(AppFont.regular, size: 18))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.9))
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    }
                    .padding(.horizontal, 20)

                    if storeManager.products.isEmpty {
                        ProgressView("Loading options...")
                            .foregroundColor(.white)
                            .padding(.top, 30)
                    } else {
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
                    }

                    VStack(spacing: 5) {
                        Button(action: {
                            isRestoring = true
                            storeManager.restorePurchases()
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isRestoring = false
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
                                        .font(.custom(AppFont.regular, size: 16))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            } else {
                                Text("Restore Purchase")
                                    .font(.custom(AppFont.regular, size: 16))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        HStack(spacing: 10) {
                            Text("Terms of Use")
                                .font(.custom(AppFont.regular, size: 14))
                                .foregroundColor(.black)
                                .underline()
                                .onTapGesture {
                                    showingTermsOfUse = true
                                }
                            
                            Text("•")
                                .font(.system(size: 14))
                                .foregroundColor(.black)
                            
                            Text("Privacy Policy")
                                .font(.custom(AppFont.regular, size: 14))
                                .foregroundColor(.black)
                                .underline()
                                .onTapGesture {
                                    showingPrivacyPolicy = true
                                }
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
            Task {
                await storeManager.requestProducts()
                await storeManager.checkEntitlements()
                if storeManager.isPremium {
                    dismiss()
                }
            }
        }
        .onChange(of: storeManager.isPremium) { newValue in
            if newValue {
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showAdView, onDismiss: {
            SwipeData.shared.refreshFromUserDefaults()
            dismiss()
        }) {
            AdView()
        }
        .sheet(isPresented: $showingTermsOfUse) {
            SafariView(url: termsOfUseURL)
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            SafariView(url: privacyPolicyURL)
        }
        .interactiveDismissDisabled(true)
    }
    
    private func getPriceString(for productID: StoreKitManager.ProductID) -> String {
        if let product = storeManager.products.first(where: { $0.id == productID.rawValue }) {
            return product.displayPrice
        }
        switch productID {
        case .monthly: return "$2.99 / Month"
        case .yearly: return "$14.99 / Year"
        case .lifetime: return "$29.99 One-Time"
        case .extraSwipes: return "$0.99 One-Time"
        }
    }
}

#Preview {
    PaywallMaxView()
}
