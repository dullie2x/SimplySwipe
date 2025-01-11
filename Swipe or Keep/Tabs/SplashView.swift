import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var simplyOffset: CGFloat = 0.0
    @State private var swipeOffset: CGFloat = 0.0

    var body: some View {
        if isActive {
            MainTabView() // Replace with your main app view
        } else {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                VStack {
                    Text("Simply")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .offset(x: simplyOffset) // Bind to offset for animation

                    Text("Swipe")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .offset(x: swipeOffset) // Bind to offset for animation
                }
            }
            .onAppear {
                // Delay the start of the animation by 0.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Trigger "Simply" animation first
                    withAnimation(.easeInOut(duration: 1.0)) {
                        simplyOffset = -UIScreen.main.bounds.width // Move "Simply" left
                    }

                    // Trigger "Swipe" animation after "Simply" finishes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { 
                        withAnimation(.easeInOut(duration: 1.0)) {
                            swipeOffset = UIScreen.main.bounds.width // Move "Swipe" right
                        }

                        // Transition to main view after "Swipe" animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isActive = true
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
