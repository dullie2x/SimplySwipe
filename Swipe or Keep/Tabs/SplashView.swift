import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var simplyOffset: CGFloat = 0.0
    @State private var swipeOffset: CGFloat = 0.0
    @State private var logoOpacity: Double = 1.0
    @State private var logoScale: CGFloat = 1.0
    
    var body: some View {
        if isActive {
            MainTabView() // Replace with your main app view
        } else {
            ZStack {
                // Background color (Black for high contrast)
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    // "Simply" above the logo
                    Text("Simply")
                        .font(.system(size: 70, weight: .heavy, design: .rounded))                        .foregroundColor(.white)
                        .offset(x: simplyOffset)
                    
                    // App Logo in the middle
                    Image("2025logo") // Ensure it's in Assets.xcassets
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220) // Slightly larger logo
                        .opacity(logoOpacity)
                        .scaleEffect(logoScale)
                    
                    // "Swipe" below the logo with BIGGER FONT
                    Text("Swipe")
                        .font(.system(size: 70, weight: .heavy, design: .rounded))                        .foregroundColor(.white)
                        .offset(x: swipeOffset)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        simplyOffset = -UIScreen.main.bounds.width // Moves left
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeInOut(duration: 1.0)) {
                            swipeOffset = UIScreen.main.bounds.width // Moves right
                        }
                        
                        // Keep the logo visible for an extra 0.5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.5)) {
                                logoOpacity = 0.0 // Fade out the logo
                            }
                            
                            // Transition to main app
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isActive = true
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SplashView()
}
