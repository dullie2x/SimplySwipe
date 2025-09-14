import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var logoOpacity: Double = 0.0
    @State private var logoScale: CGFloat = 0.9
    @State private var simplyOffset: CGFloat = 0.0
    @State private var swipeOffset: CGFloat = 0.0
    
    // Loading states
    @State private var showLoadingText = false
    @State private var loadingDots = ""
    @State private var loadingTimer: Timer?
    @State private var loadingProgress: String = "Good things take time"
    
    // Tunables: feel free to tweak
    private let minSplashSeconds: Double = 2.0     // minimum time the splash shows
    private let maxSplashSeconds: Double = 12.0    // safety timeout so you never wait forever
    
    // Reference to data manager
    @StateObject private var dataManager = MediaDataManager.shared
    
    var body: some View {
        if isActive {
            MainTabView() // shows pre-loaded data
        } else {
            if #available(iOS 17.0, *) {
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 30) {
                        Spacer()
                        
                        Image("orca8")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .opacity(logoOpacity)
                            .scaleEffect(logoScale)
                        
                        VStack(spacing: 5) {
                            Text("simply")
                                .font(.custom(AppFont.regular, size: 36))
                                .foregroundColor(.white)
                                .offset(x: simplyOffset)
                            
                            Text("swipe")
                                .font(.custom(AppFont.regular, size: 36))
                                .foregroundColor(.white)
                                .offset(x: swipeOffset)
                        }
                        
                        Spacer()
                        
                        if showLoadingText {
                            VStack(spacing: 12) {
                                Text("\(loadingProgress)\(loadingDots)")
                                    .font(.custom(AppFont.regular, size: 16))
                                    .foregroundColor(.white.opacity(0.7))
                                    .animation(.easeInOut(duration: 0.3), value: loadingDots)
                                    .animation(.easeInOut(duration: 0.3), value: loadingProgress)
                                
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
                    Task { await gateAndProceedWithTimeout() } // ⬅️ gate the exit here
                }
                .onDisappear {
                    loadingTimer?.invalidate()
                }
                .onChange(of: dataManager.isDataLoaded) { _, isLoaded in
                    if isLoaded {
                        loadingProgress = "Almost there"
                    }
                }
            } else {
                // Fallback on earlier versions if needed
            }
        }
    }
    
    private func startSplashSequence() {
        // Fade in logo
        withAnimation(.easeIn(duration: 0.8)) {
            logoOpacity = 1.0
            logoScale = 1.0
        }
        // Text slides
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.6)) { simplyOffset = -UIScreen.main.bounds.width }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.6)) { swipeOffset = UIScreen.main.bounds.width }
            }
        }
        // Loading text appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 0.5)) { showLoadingText = true }
            startLoadingAnimation()
        }
        // NOTE: removed the old hard-coded 10s exit
    }
    
    // Gate: wait for (min splash elapsed AND data loaded) OR timeout
    private func gateAndProceedWithTimeout() async {
        // Minimum splash time
        try? await Task.sleep(nanoseconds: UInt64(minSplashSeconds * 1_000_000_000))
        
        // Run the two tasks in parallel
        let loadTask = Task { await dataManager.loadAllData() }
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(maxSplashSeconds * 1_000_000_000))
        }
        
        // Wait until either finishes
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadTask.value }
            group.addTask { await timeoutTask.value }
            _ = await group.next() // returns as soon as the first one completes
            group.cancelAll()      // cancel the slower one
        }
        
        // Transition out
        withAnimation(.easeOut(duration: 0.5)) {
            logoOpacity = 0.0
            showLoadingText = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isActive = true
        }
    }

    
    private func startLoadingAnimation() {
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                switch loadingDots.count {
                case 0: loadingDots = "."
                case 1: loadingDots = ".."
                case 2: loadingDots = "..."
                default: loadingDots = ""
                }
            }
        }
    }
}

#Preview {
    SplashView()
}
