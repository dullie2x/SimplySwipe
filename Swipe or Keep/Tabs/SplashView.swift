import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var progress: CGFloat = 0.0

    var body: some View {
        if isActive {
            MainTabView() // Replace with your main app view
        } else {
            VStack {
                Text("Simply Swipe")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()

                // Loading Bar
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 10)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: progress, height: 10)
                        .animation(.easeInOut(duration: 3.0), value: progress)
                }
                .padding(.horizontal, 50)
                .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .edgesIgnoringSafeArea(.all) // Ensure it fills the entire screen
            .onAppear {
                // Simulate progress
                Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
                    if progress < UIScreen.main.bounds.width - 100 {
                        progress += 5 // Adjust the increment to speed up or slow down
                    } else {
                        timer.invalidate()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isActive = true
                        }
                    }
                }
            }
        }
    }
}
