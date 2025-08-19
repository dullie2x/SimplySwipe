import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var logoOpacity: Double = 0.0
    @State private var logoScale: CGFloat = 0.9
    @State private var simplyOffset: CGFloat = 0.0
    @State private var swipeOffset: CGFloat = 0.0
    
    // Add loading states
    @State private var showLoadingText = false
    @State private var loadingDots = ""
    @State private var loadingTimer: Timer?
    @State private var loadingProgress: String = "Good things take time"
    
    // Reference to data manager
    @StateObject private var dataManager = MediaDataManager.shared
    
    var body: some View {
        if isActive {
            MainTabView() // This will now show pre-loaded data
        } else {
            if #available(iOS 17.0, *) {
                ZStack {
                    // Simple solid background
                    Color.black
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 30) {
                        Spacer()
                        
                        // App Logo centered
                        Image("logo2") // Ensure it's in Assets.xcassets
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .opacity(logoOpacity)
                            .scaleEffect(logoScale)
                        
                        // App name stacked below logo
                        VStack(spacing: 5) {
                            Text("Simply")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .offset(x: simplyOffset)
                            
                            Text("Swipe")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .offset(x: swipeOffset)
                        }
                        
                        Spacer()
                        
                        // Loading text (appears after main animation)
                        if showLoadingText {
                            VStack(spacing: 12) {
                                Text("\(loadingProgress)\(loadingDots)")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .animation(.easeInOut(duration: 0.3), value: loadingDots)
                                    .animation(.easeInOut(duration: 0.3), value: loadingProgress)
                                
                                // Simple progress indicator
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.7)))
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .padding(.bottom, 60)
                        }
                    }
                }
                .onAppear {
                    startSplashSequence()
                    startPreloading() // ← Start loading data during splash
                }
                .onDisappear {
                    loadingTimer?.invalidate()
                }
                .onChange(of: dataManager.isDataLoaded) { _, isLoaded in
                    if isLoaded {
                        // Data is loaded, but still wait for minimum time
                        loadingProgress = "Almost there"
                    }
                }
            } else {
                // Fallback on earlier versions
            }
        }
    }
    
    private func startSplashSequence() {
        // Simple fade in
        withAnimation(.easeIn(duration: 0.8)) {
            logoOpacity = 1.0
            logoScale = 1.0
        }
        
        // Animate the text after logo appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Animate "Simply" sliding off to the left
            withAnimation(.easeInOut(duration: 0.6)) {
                simplyOffset = -UIScreen.main.bounds.width
            }
            
            // Animate "Swipe" sliding off to the right with slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    swipeOffset = UIScreen.main.bounds.width
                }
            }
        }
        
        // Show loading text after main animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showLoadingText = true
            }
            startLoadingAnimation()
        }
        
        // Extended delay - transition to main app after 10 seconds total
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                logoOpacity = 0.0
                showLoadingText = false
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isActive = true
            }
        }
    }
    
    // NEW: Start preloading data during splash
    private func startPreloading() {
        Task {
            await dataManager.loadAllData()
        }
    }
    
    private func startLoadingAnimation() {
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                switch loadingDots.count {
                case 0:
                    loadingDots = "."
                case 1:
                    loadingDots = ".."
                case 2:
                    loadingDots = "..."
                default:
                    loadingDots = ""
                }
            }
        }
    }
}

#Preview {
    SplashView()
}
