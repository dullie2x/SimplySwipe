import SwiftUI
import Photos
import AVKit

// Cache manager class to hold reference-type caches
class MediaCacheManager {
    let preloadedPlayers = NSCache<NSNumber, CachedPlayer>()
    let highQualityImageCache = NSCache<NSNumber, UIImage>()
    let lowQualityImageCache = NSCache<NSNumber, UIImage>()
    
    init() {
        preloadedPlayers.countLimit = 5
        highQualityImageCache.countLimit = 5
        lowQualityImageCache.countLimit = 10
    }
    
    func getPlayer(for index: Int) -> AVQueuePlayer? {
        return preloadedPlayers.object(forKey: NSNumber(value: index))?.player
    }
    
    func getHighQualityImage(for index: Int) -> UIImage? {
        return highQualityImageCache.object(forKey: NSNumber(value: index))
    }
    
    func getLowQualityImage(for index: Int) -> UIImage? {
        return lowQualityImageCache.object(forKey: NSNumber(value: index))
    }
    
    func cleanupOldContent(before index: Int) {
        // Only clean up if we've advanced far enough
        guard index > 2 else { return }
        
        // Clean up resources for items we've passed (keep the last 2)
        for i in 0..<(index - 2) {
            let indexNumber = NSNumber(value: i)
            
            // Clean up video player
            if let cachedPlayer = preloadedPlayers.object(forKey: indexNumber) {
                cachedPlayer.player.pause()
                cachedPlayer.player.replaceCurrentItem(with: nil)
                preloadedPlayers.removeObject(forKey: indexNumber)
            }
            
            // Clean up images
            highQualityImageCache.removeObject(forKey: indexNumber)
            lowQualityImageCache.removeObject(forKey: indexNumber)
        }
    }
}

// Wrapper class for caching AVPlayer since NSCache requires reference types
class CachedPlayer {
    let player: AVQueuePlayer
    let looper: AVPlayerLooper?
    
    init(player: AVQueuePlayer, looper: AVPlayerLooper?) {
        self.player = player
        self.looper = looper
    }
}

struct SwipeStack: View {
    @State private var offset = CGSize.zero
    @State private var currentIndex = 0
    @State private var paginatedMediaItems: [PHAsset] = []
    @State private var mediaSize: String = "0 MB"
    @State private var isLoading = true
    @State private var showBatchExhaustedNotice = false
    @State private var swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
    @State private var totalMediaCount = 0
    
    // NSCache objects for better memory management via reference type
    private let cacheManager = MediaCacheManager()
    
    private let pageSize = 30
    
    var body: some View {
        ZStack {
            // Black background applied to entire view
            Color.black.edgesIgnoringSafeArea(.all)
            
            if isLoading {
                // Enhanced loading view without background that might cause outline
                VStack(spacing: 25) {
                    // Green glowing circle with spinner - no background on this container
                    ZStack {
                        // Outer glow effect
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .blur(radius: 10)
                        
                        // Inner circle
                        Circle()
                            .fill(Color.black)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.green.opacity(0.8), Color.green.opacity(0.4)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                        
                        // Progress spinner
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.green))
                    }
                    
                    // Loading text
                    Text("Getting Things Ready!")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .shadow(color: Color.green.opacity(0.5), radius: 2)
                }
                // Removed padding that might cause outline
                .scaleEffect(1.0)
                .animation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true), value: UUID())
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        topBar()
                        swipeableStack(geometry)
                    }
                }
            }
            
            if showBatchExhaustedNotice {
                batchExhaustedNotice()
            }
        }
        .onAppear {
            MediaManager.shared.initializeAudioSession()
            fetchMedia()
        }
    }
    
    private func topBar() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Size: \(mediaSize)")
                    .font(.title2.weight(.heavy))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .onChange(of: currentIndex) { _ in
                        mediaSize = MediaManager.shared.updateMediaSize(for: paginatedMediaItems, index: currentIndex)
                        preloadImages()
                        MediaManager.shared.pauseNonFocusedVideos(players: cacheManager.preloadedPlayers, currentIndex: currentIndex)
                        cacheManager.cleanupOldContent(before: currentIndex) // Clean up resources for items we've passed
                    }
            }
            Spacer()
            Button(action: goBack) {
                Image(systemName: "arrow.uturn.left") // Undo arrow icon
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(currentIndex > 0 ? .green : .gray) // Disable if no previous media
                    .padding(8)
            }
            .disabled(currentIndex == 0) // Disable button if at the first item
        }
        .padding(.horizontal, 20)
    }
    
    // Function to go back to the previous media
    private func goBack() {
        if currentIndex > 0 {
            currentIndex -= 1
            preloadImages()
            MediaManager.shared.pauseNonFocusedVideos(players: cacheManager.preloadedPlayers, currentIndex: currentIndex)
        }
    }
    
    private func swipeableStack(_ geometry: GeometryProxy) -> some View {
        let topBarHeight: CGFloat = 50  // Approximate height of the top bar
        let bottomTabHeight: CGFloat = 80  // Approximate height of the bottom tab bar
        let availableHeight = geometry.size.height - (topBarHeight + bottomTabHeight) // Space between top bar & tab bar
        
        return ZStack {
            ForEach(currentIndex..<min(currentIndex + 2, paginatedMediaItems.count), id: \.self) { index in
                if index < paginatedMediaItems.count {
                    MediaCardView(
                        asset: paginatedMediaItems[index],
                        size: CGSize(
                            width: geometry.size.width,  // Full width
                            height: availableHeight      // Fit within available space
                        ),
                        offset: index == currentIndex ? $offset : .constant(.zero),
                        onSwiped: handleSwipe,
                        player: cacheManager.getPlayer(for: index),
                        highQualityImage: cacheManager.getHighQualityImage(for: index),
                        lowQualityImage: cacheManager.getLowQualityImage(for: index)
                    )
                    .zIndex(Double(-index))
                    .offset(y: topBarHeight / 2)  // Pushes media down slightly so top bar is always visible
                    .scaleEffect(index == currentIndex ? 1.0 : 0.95)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.2), value: currentIndex)
                }
            }
        }
        .frame(width: geometry.size.width, height: availableHeight) // Ensures correct size
    }
    
    // In the fetchMedia method, prioritize low-quality images first
    private func fetchMedia() {
        isLoading = true
        MediaManager.shared.fetchMedia { fetchedMedia, totalCount in
            self.paginatedMediaItems = fetchedMedia
            self.totalMediaCount = totalCount
            self.currentIndex = 0
            
            // Immediately fetch high-quality image for the first item
            if !fetchedMedia.isEmpty {
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true
                options.isSynchronous = true // Make this synchronous for first image only
                
                let manager = PHImageManager.default()
                manager.requestImage(
                    for: fetchedMedia[0],
                    targetSize: CGSize(width: 1080, height: 1080),
                    contentMode: .aspectFit,
                    options: options
                ) { result, _ in
                    if let image = result {
                        DispatchQueue.main.async {
                            self.cacheManager.highQualityImageCache.setObject(image, forKey: NSNumber(value: 0))
                            self.isLoading = false
                            self.mediaSize = MediaManager.shared.updateMediaSize(for: self.paginatedMediaItems, index: self.currentIndex)
                        }
                    } else {
                        // If high-quality image fails, still proceed with low-quality
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.mediaSize = MediaManager.shared.updateMediaSize(for: self.paginatedMediaItems, index: self.currentIndex)
                        }
                    }
                }
            }
            
            // Continue with rest of media loading in background
            DispatchQueue.global(qos: .userInitiated).async {
                // Preload videos
                MediaManager.shared.preloadVideos(for: self.paginatedMediaItems) { index, player, looper in
                    if let player = player {
                        let cachedPlayer = CachedPlayer(player: player, looper: looper)
                        self.cacheManager.preloadedPlayers.setObject(cachedPlayer, forKey: NSNumber(value: index))
                    }
                }
                
                // Prefetch low-quality images for rest of items
                MediaManager.shared.prefetchLowQualityImages(for: self.paginatedMediaItems) { index, image in
                    if let image = image, index > 0 { // Skip first item which we loaded high-quality
                        self.cacheManager.lowQualityImageCache.setObject(image, forKey: NSNumber(value: index))
                    }
                }
                
                // Start loading high-quality images for items past the first one
                for i in 1..<min(5, self.paginatedMediaItems.count) {
                    self.preloadHighQualityImage(for: i)
                }
            }
        }
    }
    
    // Separate method for high-quality image loading
    private func preloadHighQualityImage(for index: Int) {
        MediaManager.shared.fetchHighQualityImage(for: index, in: paginatedMediaItems) { index, image in
            if let image = image {
                self.cacheManager.highQualityImageCache.setObject(image, forKey: NSNumber(value: index))
            }
        }
    }
    
    // Update preloadImages to load more images ahead
    private func preloadImages() {
        // Preload several images ahead
        for offset in 0...3 {
            let index = currentIndex + offset
            if index < paginatedMediaItems.count {
                preloadHighQualityImage(for: index)
            }
        }
    }
    
    private func handleSwipe(direction: SwipeDirection) {
        if currentIndex < paginatedMediaItems.count {
            let currentItem = paginatedMediaItems[currentIndex]
            SwipedMediaManager.shared.addSwipedMedia(currentItem, toTrash: direction == .left)
            
            // Pause and clean up current video if needed
            if let cachedPlayer = cacheManager.preloadedPlayers.object(forKey: NSNumber(value: currentIndex)) {
                cachedPlayer.player.pause()
                cachedPlayer.player.volume = 0.0
            }
        }
        
        swipeCount += 1
        UserDefaults.standard.set(swipeCount, forKey: "swipeCount")
        
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.15)) {
            offset.width = direction == .left ? -1000 : 1000
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            offset = .zero
            currentIndex += 1
            
            if self.currentIndex < self.paginatedMediaItems.count {
                self.preloadImages()
                self.cacheManager.cleanupOldContent(before: self.currentIndex) // Explicitly clean up old content
                MediaManager.shared.pauseNonFocusedVideos(players: self.cacheManager.preloadedPlayers, currentIndex: self.currentIndex)
            } else {
                self.handleBatchExhausted()
            }
        }
    }
    
    private func handleBatchExhausted() {
        // Stop all video players before showing the notice
        for i in 0..<paginatedMediaItems.count {
            if let cachedPlayer = cacheManager.preloadedPlayers.object(forKey: NSNumber(value: i)) {
                cachedPlayer.player.pause()
                cachedPlayer.player.replaceCurrentItem(with: nil)
            }
        }
        
        // Clear all video players from cache
        cacheManager.preloadedPlayers.removeAllObjects()
        
        showBatchExhaustedNotice = true
        isLoading = false
    }
    
    private func batchExhaustedNotice() -> some View {
        VStack(spacing: 20) {
            // Title with icon
            HStack {
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 24))
                
                Text("Quick Pause")
                    .font(.title3.bold())
                    .foregroundColor(.white)
            }
            
            // Main message
            Text("Consider emptying your trash to free up space.")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Continue button only
            Button(action: {
                showBatchExhaustedNotice = false
                fetchMedia()
            }) {
                HStack {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 14))
                    Text("Continue")
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .frame(minWidth: 160)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green.opacity(0.8), Color.blue.opacity(0.8)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding(.vertical, 25)
        .padding(.horizontal, 20)
        .frame(maxWidth: 350)
        .background(
            // Custom background with gradient edge
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.green.opacity(0.7),
                                    Color.blue.opacity(0.5),
                                    Color.black.opacity(0.0),
                                    Color.black.opacity(0.0),
                                    Color.green.opacity(0.7)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
        )
        .shadow(color: Color.green.opacity(0.3), radius: 15, x: 0, y: 0)
    }
}
