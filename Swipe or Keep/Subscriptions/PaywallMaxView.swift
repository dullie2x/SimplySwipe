import SwiftUI
import SafariServices

struct PaywallMaxView: View {
    @Environment(\.dismiss) var dismiss
    @State private var animate = false
    @State private var showAdView = false // Controls AdView presentation
    @State private var showingTermsOfUse = false // Controls Terms & Conditions sheet
    
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.red.opacity(0.7), Color.orange.opacity(0.7)]),
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
                        Text("You're Out of Free Swipes!")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(radius: 5)
                        
                        Text("Choose an option below:")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }

                    // Options
                    Group {
                        // Option 1
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Wait Until Tomorrow for Free Swipes")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.7))
                                .cornerRadius(12)
                                .shadow(radius: 5)
                        }
                        .padding(.horizontal, 20)

                        // Option 2
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
                        .padding(.horizontal, 20)
                    }

                    // Option 3 - Upgrades
                    VStack(spacing: 15) {
                        PaywallOption(title: "Unlimited Swipes - Monthly", price: "$2.99 / Month", highlight: false, animate: $animate) {}
                        PaywallOption(title: "Unlimited Swipes - Yearly", price: "$14.99 / Year", highlight: true, animate: $animate) {}
                        PaywallOption(title: "Lifetime Access", price: "$29.99 One-Time", highlight: false, animate: $animate) {}
                        PaywallOption(title: "200 Extra Swipes", price: "$0.99 One-Time", highlight: false, animate: $animate) {}
                    }
                    .padding(.horizontal, 20)

                    // Terms & Restore
                    VStack(spacing: 5) {
                        Button("Restore Purchase") {}
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
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
        .onAppear { animate.toggle() }
        .fullScreenCover(isPresented: $showAdView) {
            AdView()
        }
        .sheet(isPresented: $showingTermsOfUse) {
            SafariView(url: termsOfUseURL)
        }
        .interactiveDismissDisabled(true)
    }

}


struct PaywallMaxView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallMaxView()
    }
}
