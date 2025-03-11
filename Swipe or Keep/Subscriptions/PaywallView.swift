import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) var dismiss
    @State private var animate = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.7), Color.blue.opacity(0.7)]),
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
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(radius: 5)
                    }
                    .padding(.top, 15)
                    .padding(.trailing, 15)
                }
                
                Spacer()
                
                // Title & Subtitle
                VStack(spacing: 10) {
                    Text("Unlock Unlimited Swipes")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                    
                    Text("Upgrade now to keep swiping without limits.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .padding(.top, -20)

                // Pricing Options
                VStack(spacing: 20) {
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
            .scaleEffect(animate ? 1.05 : 1.0)
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
