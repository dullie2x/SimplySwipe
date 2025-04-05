import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var simplyOffset: CGFloat = 0.0
    @State private var swipeOffset: CGFloat = 0.0
    @State private var logoOpacity: Double = 0.0
    @State private var logoScale: CGFloat = 0.8
    @State private var backgroundGradient = [Color.black, Color(red: 0.1, green: 0.1, blue: 0.2)]
    @State private var animateGradient = false
    
    // Add a pulsing effect to the logo
    @State private var pulsate = false
    
    var body: some View {
        if isActive {
            MainTabView() // Replace with your main app view
        } else {
            ZStack {
                // Animated gradient background
                LinearGradient(
                    gradient: Gradient(colors: backgroundGradient),
                    startPoint: animateGradient ? .topLeading : .bottomTrailing,
                    endPoint: animateGradient ? .bottomTrailing : .topLeading
                )
                .edgesIgnoringSafeArea(.all)
                .animation(
                    Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true),
                    value: animateGradient
                )
                
                // Particle effect in background
//                ParticleEffect()
                    .opacity(0.4)
                
                VStack(spacing: 30) {
                    // "Simply" above the logo with better animation
                    Text("Simply")
                        .font(.system(size: 70, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .offset(x: simplyOffset)
                        .shadow(color: .blue.opacity(0.5), radius: 10, x: 0, y: 5)
                    
                    // App Logo in the middle with enhanced animations
                    Image("2025logo") // Ensure it's in Assets.xcassets
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .opacity(logoOpacity)
                        .scaleEffect(logoScale + (pulsate ? 0.05 : 0))
                        .shadow(color: .white.opacity(0.7), radius: 20, x: 0, y: 0)
                        .animation(
                            Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: pulsate
                        )
                    
                    // "Swipe" below the logo with enhanced animation
                    Text("Swipe")
                        .font(.system(size: 70, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .offset(x: swipeOffset)
                        .shadow(color: .blue.opacity(0.5), radius: 10, x: 0, y: 5)
                }
            }
            .onAppear {
                // Start the gradient animation
                animateGradient = true
                
                // Start the pulsing animation
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsate = true
                }
                
                // Initial fade-in of the logo
                withAnimation(.easeIn(duration: 1.0)) {
                    logoOpacity = 1.0
                    logoScale = 1.0
                }
                
                // Start the word animations after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // Animate "Simply" sliding off to the left
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                        simplyOffset = -UIScreen.main.bounds.width
                    }
                    
                    // After a brief pause, animate "Swipe" sliding off to the right
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                            swipeOffset = UIScreen.main.bounds.width
                        }
                        
                        // Fade out the logo with a slight delay and then transition to main app
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeOut(duration: 0.8)) {
                                logoOpacity = 0.0
                                logoScale = 1.3 // Grow slightly as it fades out
                            }
                            
                            // Transition to main app
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                isActive = true
                            }
                        }
                    }
                }
            }
        }
    }
}

//// Particle effect component for background visual interest
//struct ParticleEffect: View {
//    @State private var time = 0.0
//    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
//    
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack {
//                ForEach(0..<20) { i in
//                    Circle()
//                        .fill(Color.white.opacity(0.7))
//                        .frame(width: randomSize(seed: i), height: randomSize(seed: i))
//                        .position(
//                            x: randomPosition(max: geometry.size.width, seed: i, time: time),
//                            y: randomPosition(max: geometry.size.height, seed: i + 20, time: time)
//                        )
//                        .blendMode(.screen)
//                }
//            }
//        }
//        .onReceive(timer) { _ in
//            time += 0.1
//        }
//    }
//    
//    // Helper functions for the particle effect
//    func randomSize(seed: Int) -> CGFloat {
//        let base = sin(Double(seed) * 0.3) * 0.5 + 0.5
//        return CGFloat(base * 15 + 2)
//    }
//    
//    func randomPosition(max: CGFloat, seed: Int, time: Double) -> CGFloat {
//        let period = sin(Double(seed) * 0.1) * 10 + 20
//        let amplitude = max * 0.25
//        let base = sin(time / period + Double(seed)) * Double(amplitude)
//        return CGFloat(base + Double(max) / 2)
//    }
//}


#Preview {
    SplashView()
}
