import SwiftUI
import Photos
import AVKit

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
    @State private var mediaItems: [PHAsset] = []
    @State private var paginatedMediaItems: [PHAsset] = []
    @State private var mediaSize: String = "0 MB"
    @State private var isLoading = true
    @State private var loadingProgress: Double = 0.0
    @State private var swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
    
    // Use NSCache for better memory management
    private let preloadedPlayers: NSCache<NSNumber, CachedPlayer>
    private let highQualityImageCache: NSCache<NSNumber, UIImage>
    private let lowQualityImageCache: NSCache<NSNumber, UIImage>
    
    // Optimize page size and preload window
    private let pageSize = 20
    private let preloadWindow = 5
    
    init() {
        // Configure cache limits
        let highQualityCache = NSCache<NSNumber, UIImage>()
        highQualityCache.countLimit = 10
        self.highQualityImageCache = highQualityCache
        
        let lowQualityCache = NSCache<NSNumber, UIImage>()
        lowQualityCache.countLimit = 15
        self.lowQualityImageCache = lowQualityCache
        
        let playerCache = NSCache<NSNumber, CachedPlayer>()
        playerCache.countLimit = 5
        self.preloadedPlayers = playerCache
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top inline navigation bar
            HStack {
                if !isLoading && currentIndex < mediaItems.count {
                    // Size on the left
                    Text(mediaSize)
                        .font(Font.title2.weight(.heavy))
                        .foregroundColor(.green)
                        .padding(8)
                        .onChange(of: currentIndex) { _ in
                            updateMediaSize()
                            preloadContentForCurrentIndex()
                            cleanupOldContent()
                            pauseNonFocusedVideos()
                        }
                    
                    Spacer() // Push size to left and undo button to right
                    
                    // Go back button on the right
                    Button(action: goBack) {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(currentIndex > 0 ? .green : .gray)
                            .padding(8)
                    }
                    .disabled(currentIndex == 0) // Disable button if at the first item
                } else {
                    Spacer()
                }
            }
            .padding(.vertical, 5)
            .background(Color.black)
            .zIndex(2) // Ensure navbar stays on top
            
            // Main content
            ZStack {
                if isLoading {
                    VStack(spacing: 25) {
                        // Green glowing circle with spinner
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
                            
                            // Progress view with percentage
                            VStack(spacing: 5) {
                                ProgressView(value: loadingProgress, total: 1.0)
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color.green))
                                    .scaleEffect(1.5)
                                
                                Text("\(Int(loadingProgress * 100))%")
                                    .font(.headline.bold())
                                    .foregroundColor(.green)
                            }
                        }
                        
                        // Loading text
                        Text("Loading Media...")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .shadow(color: Color.green.opacity(0.5), radius: 2)
                    }
                    .padding(30)
                    // Add a subtle animation
                    .scaleEffect(1.0)
                    .animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: UUID())
                } else if mediaItems.isEmpty {
                    VStack {
                        Text("No Media Found")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                            .padding()
                    }
                } else {
                    GeometryReader { geometry in
                        ZStack {
                            // Only render at most 2 cards at a time to reduce memory
                            ForEach(currentIndex..<min(currentIndex + 2, paginatedMediaItems.count), id: \.self) { index in
                                if index < paginatedMediaItems.count {
                                    MediaCardView(
                                        asset: paginatedMediaItems[index],
                                        size: CGSize(width: geometry.size.width - CGFloat((index - currentIndex) * 15),
                                                   height: geometry.size.height - CGFloat((index - currentIndex) * 15)),
                                        offset: index == currentIndex ? $offset : .constant(.zero),
                                        onSwiped: handleSwipe,
                                        player: getPlayer(for: index),
                                        highQualityImage: getHighQualityImage(for: index),
                                        lowQualityImage: getLowQualityImage(for: index)
                                    )
                                    .zIndex(Double(-index))
                                    .offset(x: CGFloat((index - currentIndex) * 10), y: CGFloat((index - currentIndex) * 10))
                                    .scaleEffect(index == currentIndex ? 1.0 : 0.95, anchor: .center)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.2), value: currentIndex)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear(perform: initializeAudioSession)
        .onAppear(perform: fetchMedia)
        .navigationBarHidden(true)
    }
    
    // Function to go back to the previous media
    private func goBack() {
        if currentIndex > 0 {
            currentIndex -= 1
            updateMediaSize()
            preloadContentForCurrentIndex()
            pauseNonFocusedVideos()
        }
    }
    
    // Helper methods for accessing cached content
    private func getPlayer(for index: Int) -> AVQueuePlayer? {
        return preloadedPlayers.object(forKey: NSNumber(value: index))?.player
    }
    
    private func getHighQualityImage(for index: Int) -> UIImage? {
        return highQualityImageCache.object(forKey: NSNumber(value: index))
    }
    
    private func getLowQualityImage(for index: Int) -> UIImage? {
        return lowQualityImageCache.object(forKey: NSNumber(value: index))
    }
    
    func initializeAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
    }
    
    func fetchMedia() {
        isLoading = true
        loadingProgress = 0.0
        
        DispatchQueue.global(qos: .userInitiated).async {
            MediaManager.shared.fetchMedia { fetchedMedia, _ in
                DispatchQueue.main.async {
                    if fetchedMedia.isEmpty {
                        self.isLoading = false
                        self.loadingProgress = 1.0
                        print("No media items found.")
                        return
                    }
                    
                    self.mediaItems = fetchedMedia
                    self.paginatedMediaItems = Array(fetchedMedia.prefix(self.pageSize))
                    self.updateMediaSize()
                    self.preloadInitialContent()
                }
            }
        }
    }
    
    func preloadInitialContent() {
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()
            
            // Only preload first few items to reduce initial memory footprint
            for (index, asset) in self.paginatedMediaItems.prefix(self.preloadWindow).enumerated() {
                group.enter()
                if asset.mediaType == .video {
                    self.preloadVideo(for: index, asset: asset) {
                        group.leave()
                    }
                } else {
                    // First load a thumbnail for quick display
                    self.fetchThumbnailImage(for: index, asset: asset) {
                        // Then load high quality in background
                        self.fetchHighQualityImage(for: index, asset: asset) {
                            group.leave()
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.loadingProgress = Double(index + 1) / Double(min(self.preloadWindow, self.paginatedMediaItems.count))
                }
            }
            
            group.notify(queue: .main) {
                self.isLoading = false
                
                // Start playing video if the first item is a video
                if self.currentIndex < self.paginatedMediaItems.count,
                   self.paginatedMediaItems[self.currentIndex].mediaType == .video,
                   let cachedPlayer = self.preloadedPlayers.object(forKey: NSNumber(value: self.currentIndex)) {
                    cachedPlayer.player.volume = 0.0
                    cachedPlayer.player.play()
                }
            }
        }
    }
    
    func preloadContentForCurrentIndex() {
        pauseNonFocusedVideos()
        
        // First, check if we're at or past the end
        guard currentIndex < paginatedMediaItems.count else {
            // Check if we need to loop back to the beginning
            if currentIndex >= mediaItems.count && mediaItems.count > 0 {
                currentIndex = 0
                resetAndReload()
            }
            return
        }
        
        // Preload next few items
        let startPreload = currentIndex + 1
        // Make sure we don't go out of bounds
        guard startPreload < paginatedMediaItems.count else { return }
        
        let endPreload = min(startPreload + preloadWindow, paginatedMediaItems.count)
        
        for index in startPreload..<endPreload {
            let asset = paginatedMediaItems[index]
            if asset.mediaType == .video {
                // Only preload if not already loaded
                if preloadedPlayers.object(forKey: NSNumber(value: index)) == nil {
                    preloadVideo(for: index, asset: asset, completion: nil)
                }
            } else {
                // Always load thumbnail first for faster display
                if lowQualityImageCache.object(forKey: NSNumber(value: index)) == nil {
                    fetchThumbnailImage(for: index, asset: asset) {
                        // Then load high quality in background
                        if self.highQualityImageCache.object(forKey: NSNumber(value: index)) == nil {
                            self.fetchHighQualityImage(for: index, asset: asset, completion: nil)
                        }
                    }
                } else if highQualityImageCache.object(forKey: NSNumber(value: index)) == nil {
                    fetchHighQualityImage(for: index, asset: asset, completion: nil)
                }
            }
        }
        
        // Load more paginated items if needed
        fetchMoreMediaIfNeeded()
    }
    
    private func resetAndReload() {
        // Clean all caches
        preloadedPlayers.removeAllObjects()
        highQualityImageCache.removeAllObjects()
        lowQualityImageCache.removeAllObjects()
        
        // Reload paginated items and preload content
        paginatedMediaItems = Array(mediaItems.prefix(pageSize))
        updateMediaSize()
        preloadContentForCurrentIndex()
    }
    
    func cleanupOldContent() {
        // Only attempt cleanup if we've advanced far enough
        guard currentIndex > 2 else { return }
        
        // Release memory for items we've passed
        for index in 0..<(currentIndex - 2) {
            let indexNumber = NSNumber(value: index)
            
            // Clean up video players that are no longer needed
            if let cachedPlayer = preloadedPlayers.object(forKey: indexNumber) {
                cachedPlayer.player.pause()
                cachedPlayer.player.replaceCurrentItem(with: nil)
                preloadedPlayers.removeObject(forKey: indexNumber)
            }
            
            // Also clean up cached images
            highQualityImageCache.removeObject(forKey: indexNumber)
            lowQualityImageCache.removeObject(forKey: indexNumber)
        }
    }
    
    func preloadVideo(for index: Int, asset: PHAsset, completion: (() -> Void)?) {
        // Check if we already have this video loaded
        if preloadedPlayers.object(forKey: NSNumber(value: index)) != nil {
            completion?()
            return
        }
        
        let manager = PHImageManager.default()
        let options = PHVideoRequestOptions()
        options.deliveryMode = .fastFormat // Use fast format for initial load
        options.isNetworkAccessAllowed = true
        
        manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            if let playerItem = playerItem {
                DispatchQueue.main.async {
                    let player = AVQueuePlayer(playerItem: playerItem)
                    player.volume = 0.0  // Always start muted
                    let looper = AVPlayerLooper(player: player, templateItem: playerItem)
                    
                    let cachedPlayer = CachedPlayer(player: player, looper: looper)
                    self.preloadedPlayers.setObject(cachedPlayer, forKey: NSNumber(value: index))
                    
                    if index == self.currentIndex {
                        player.play()
                    }
                }
            }
            completion?()
        }
    }
    
    func pauseNonFocusedVideos() {
        // Iterate from (currentIndex-1) to (currentIndex+preloadWindow) to find video players
        for index in (currentIndex-1)...(currentIndex+preloadWindow) {
            guard index >= 0 else { continue }
            
            let indexNumber = NSNumber(value: index)
            if let cachedPlayer = preloadedPlayers.object(forKey: indexNumber) {
                if index == currentIndex {
                    cachedPlayer.player.play()
                    cachedPlayer.player.volume = 0.0
                } else {
                    cachedPlayer.player.pause()
                    cachedPlayer.player.volume = 0.0
                }
            }
        }
    }
    
    func fetchThumbnailImage(for index: Int, asset: PHAsset, completion: (() -> Void)?) {
        // Check if we already have this thumbnail
        if lowQualityImageCache.object(forKey: NSNumber(value: index)) != nil {
            completion?()
            return
        }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        
        // Request a smaller thumbnail for faster loading
        manager.requestImage(for: asset,
                            targetSize: CGSize(width: 300, height: 300),
                            contentMode: .aspectFill,
                            options: options) { result, _ in
            if let result = result {
                self.lowQualityImageCache.setObject(result, forKey: NSNumber(value: index))
            }
            completion?()
        }
    }
    
    func fetchHighQualityImage(for index: Int, asset: PHAsset, completion: (() -> Void)?) {
        // Check if we already have this image
        if highQualityImageCache.object(forKey: NSNumber(value: index)) != nil {
            completion?()
            return
        }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        // Reduce image size to 1080p instead of full resolution
        manager.requestImage(for: asset,
                            targetSize: CGSize(width: 1080, height: 1080),
                            contentMode: .aspectFit,
                            options: options) { result, _ in
            if let result = result {
                self.highQualityImageCache.setObject(result, forKey: NSNumber(value: index))
            }
            completion?()
        }
    }
    
    func fetchMoreMediaIfNeeded() {
        // More efficient pagination - only fetch next batch when needed
        if currentIndex >= paginatedMediaItems.count - preloadWindow {
            let fetchedCount = paginatedMediaItems.count
            let remainingCount = mediaItems.count - fetchedCount
            
            if remainingCount > 0 {
                let nextBatchCount = min(pageSize, remainingCount)
                let nextBatch = Array(mediaItems[fetchedCount..<(fetchedCount + nextBatchCount)])
                paginatedMediaItems.append(contentsOf: nextBatch)
            }
        }
    }
    
    func handleSwipe(direction: SwipeDirection) {
        if currentIndex < paginatedMediaItems.count {
            let currentItem = paginatedMediaItems[currentIndex]
            
            if direction == .left {
                SwipedMediaManager.shared.addSwipedMedia(currentItem, toTrash: true)
            } else if direction == .right {
                SwipedMediaManager.shared.addSwipedMedia(currentItem, toTrash: false)
            }
            
            // Increment swipe count and store
            swipeCount += 1
            UserDefaults.standard.set(swipeCount, forKey: "swipeCount")
            
            // Provide haptic feedback
            let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            feedbackGenerator.impactOccurred()
        }
        
        withAnimation(.easeInOut(duration: 0.15)) {
            offset.width = direction == .left ? -1000 : 1000
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            offset = .zero
            currentIndex += 1
            
            // Clean up old items and preload new ones
            self.cleanupOldContent()
            self.preloadContentForCurrentIndex()
            
            // If we've reached the end of all media items, loop back to start
            if self.currentIndex >= self.mediaItems.count && !self.mediaItems.isEmpty {
                self.currentIndex = 0
                self.resetAndReload()
            }
        }
    }
    
    func updateMediaSize() {
        guard currentIndex < paginatedMediaItems.count else { return }
        let asset = paginatedMediaItems[currentIndex]
        
        // Use MediaManager to get size or implement directly
        mediaSize = MediaManager.shared.updateMediaSize(for: paginatedMediaItems, index: currentIndex)
    }
}
