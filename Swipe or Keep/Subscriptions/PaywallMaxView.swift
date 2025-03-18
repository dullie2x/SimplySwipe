import SwiftUI

struct PaywallMaxView: View {
    @Environment(\.dismiss) var dismiss
    @State private var animate = false
    @State private var showAdView = false // Controls AdView presentation

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.red.opacity(0.7), Color.orange.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            
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
                
                Spacer()
                
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
                .padding(.top, -20)

                // **Option 1: Wait for Free Swipes**
                VStack(spacing: 10) {
                    Button(action: {
                        dismiss() // Just closes the paywall and lets them wait
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
                }
                .padding(.horizontal, 20)

                // **Option 2: Watch Ad for 10 More Swipes**
                VStack(spacing: 10) {
                    Button(action: {
                        showAdView = true // Show AdView without dismissing PaywallMaxView
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

                // **Option 3: Upgrade for Unlimited Swipes**
                VStack(spacing: 15) {
                    PaywallOption(title: "Unlimited Swipes - Monthly", price: "$2.99 / Month", highlight: false, animate: $animate) {
                        // Purchase logic for Monthly Plan
                    }
                    PaywallOption(title: "Unlimited Swipes - Yearly", price: "$14.99 / Year", highlight: true, animate: $animate) {
                        // Purchase logic for Yearly Plan
                    }
                    PaywallOption(title: "Lifetime Access", price: "$29.99 One-Time", highlight: false, animate: $animate) {
                        // Purchase logic for Lifetime Plan
                    }
                    PaywallOption(title: "200 Extra Swipes", price: "$0.99 One-Time", highlight: false, animate: $animate) {
                        // Purchase logic for Extra Swipes
                    }
                }
                .padding(.horizontal, 20)

                // Terms & Restore Purchase
                VStack(spacing: 5) {
                    Button("Restore Purchase") {
                        // Restore purchases logic
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    
                    Text("By subscribing, you agree to our Terms & Conditions.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 60)
                
                Spacer()
            }
        }
        .onAppear { animate.toggle() }
        .fullScreenCover(isPresented: $showAdView) {
            AdView() // Opens AdView full screen
        }
        .interactiveDismissDisabled(true) // Prevents swipe-down dismissal
    }
}

struct PaywallMaxView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallMaxView()
    }
}
