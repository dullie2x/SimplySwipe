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
    @State private var mediaDate: String = ""
    @State private var isLoading = true
    @State private var loadingProgress: Double = 0.0
    @State private var swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
    
    // Add previous indices tracking array and maximum go back count
    @State private var previousIndices: [Int] = []
    @State private var maxGoBackCount = 2
    
    // New state variables for the break feature
    @State private var showingBreakView = false
    @State private var currentBatch = 0
    @State private var isFetchingNextBatch = false
    
    // Use NSCache for better memory management
    private let preloadedPlayers: NSCache<NSNumber, CachedPlayer>
    private let highQualityImageCache: NSCache<NSNumber, UIImage>
    private let lowQualityImageCache: NSCache<NSNumber, UIImage>
    
    // Batch size for the break feature
    private let batchSize = 75
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
        ZStack {
            VStack(spacing: 0) {
                // Top inline navigation bar
                HStack {
                    if !isLoading && currentIndex < paginatedMediaItems.count {
                        // Size on the left
                        Text(mediaSize)
                            .font(Font.title2.weight(.heavy))
                            .foregroundColor(.green)
                            .padding(8)
                            .onChange(of: currentIndex) { _ in
                                updateMediaSize()
                                updateMediaDate()
                                preloadContentForCurrentIndex()
                                cleanupOldContent()
                                pauseNonFocusedVideos()
                                checkForBreak()
                            }
                        
                        Spacer() // Push size to left and center the date
                        
                        // Date in center with custom format
                        Text(mediaDate)
                            .font(Font.title2.weight(.heavy))
                            .foregroundColor(.green)
                            .padding(8)
                        
                        Spacer() // Center date and push go back to right
                        
                        // Go back button on the right
                        Button(action: goBack) {
                            Image(systemName: "arrow.uturn.left")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(!previousIndices.isEmpty ? .green : .gray)
                                .padding(8)
                        }
                        .disabled(previousIndices.isEmpty) // Disable when no history available
                    } else {
                        Spacer()
                    }
                }
                .padding(.vertical, 5)
                .background(Color.black)
                .zIndex(2) // Ensure navbar stays on top
                
                // Main content remains the same
                ZStack {
                    // Content remains the same
                    if isLoading {
                        VStack(spacing: 25) {
                            // Loading spinner (unchanged)
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
                        }
                        .padding(30)
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
                    } else if !showingBreakView {
                        GeometryReader { geometry in
                            ZStack {
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
            
            // Break view overlay
            if showingBreakView {
                BreakView(
                    batchNumber: currentBatch,
                    isLoading: $isFetchingNextBatch,
                    onContinue: fetchNextBatch
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear(perform: initializeAudioSession)
        .onAppear(perform: fetchMedia)
        .onAppear(perform: updateMediaDate)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            handleAppReturnFromBackground()
        }
        .navigationBarHidden(true)
    }
    
    // Check if we should show the break view
    private func checkForBreak() {
        // Show break view when we've reached the end of the paginated items
        // But only if we're not at the end of all media items
        if currentIndex >= paginatedMediaItems.count && currentIndex < mediaItems.count {
            // Delay showing break view by a tiny bit to ensure smooth transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    showingBreakView = true
                }
            }
        }
    }
    

    
    // Fetch next batch of items
    private func fetchNextBatch() {
        isFetchingNextBatch = true
        
        // Clear current assets to free up memory
        preloadedPlayers.removeAllObjects()
        highQualityImageCache.removeAllObjects()
        lowQualityImageCache.removeAllObjects()
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Calculate the start index for the next batch
            let startIndex = (currentBatch + 1) * batchSize
            
            // Make sure we don't go past the end of all media items
            if startIndex < mediaItems.count {
                // Calculate how many items to fetch for the next batch
                let endIndex = min(startIndex + batchSize, mediaItems.count)
                
                // Get the next batch of items
                let nextBatch = Array(mediaItems[startIndex..<endIndex])
                
                // Pre-load a few items before revealing the next batch
                let preloadGroup = DispatchGroup()
                let preloadCount = min(3, nextBatch.count)
                
                for i in 0..<preloadCount {
                    let asset = nextBatch[i]
                    preloadGroup.enter()
                    
                    if asset.mediaType == .video {
                        self.preloadVideo(for: i, asset: asset) {
                            preloadGroup.leave()
                        }
                    } else {
                        self.fetchThumbnailImage(for: i, asset: asset) {
                            // Then load high quality in background
                            self.fetchHighQualityImage(for: i, asset: asset) {
                                preloadGroup.leave()
                            }
                        }
                    }
                }
                
                preloadGroup.notify(queue: .main) {
                    // Replace the paginated items with the new batch
                    self.paginatedMediaItems = nextBatch
                    
                    // Reset currentIndex to the beginning of the new batch
                    self.currentIndex = 0
                    
                    // Clear previous history as we're starting a new batch
                    self.previousIndices = []
                    
                    // Increment batch counter
                    self.currentBatch += 1
                    
                    // Update display for the first item in the new batch
                    self.updateMediaSize()
                    self.updateMediaDate()
                    
                    // Hide break view
                    withAnimation {
                        self.showingBreakView = false
                        self.isFetchingNextBatch = false
                    }
                    
                    // Continue preloading more items in background
                    self.preloadContentForCurrentIndex()
                }
            } else {
                // We've reached the end, loop back to the beginning
                let firstBatch = Array(self.mediaItems.prefix(min(self.batchSize, self.mediaItems.count)))
                
                // Pre-load a few items before revealing the first batch
                let preloadGroup = DispatchGroup()
                let preloadCount = min(3, firstBatch.count)
                
                for i in 0..<preloadCount {
                    let asset = firstBatch[i]
                    preloadGroup.enter()
                    
                    if asset.mediaType == .video {
                        self.preloadVideo(for: i, asset: asset) {
                            preloadGroup.leave()
                        }
                    } else {
                        self.fetchThumbnailImage(for: i, asset: asset) {
                            self.fetchHighQualityImage(for: i, asset: asset) {
                                preloadGroup.leave()
                            }
                        }
                    }
                }
                
                preloadGroup.notify(queue: .main) {
                    self.currentBatch = 0
                    self.currentIndex = 0
                    self.paginatedMediaItems = firstBatch
                    self.previousIndices = []
                    
                    // Update display for the first item
                    self.updateMediaSize()
                    self.updateMediaDate()
                    
                    // Hide break view
                    withAnimation {
                        self.showingBreakView = false
                        self.isFetchingNextBatch = false
                    }
                    
                    // Continue preloading more items in background
                    self.preloadContentForCurrentIndex()
                }
            }
        }
    }
    
    // Add function to update media date
    func updateMediaDate() {
        guard currentIndex < paginatedMediaItems.count else {
            mediaDate = ""
            return
        }
        
        let asset = paginatedMediaItems[currentIndex]
        
        // Create date formatter with custom format (month day, year)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        
        // Format creation date
        if let creationDate = asset.creationDate {
            mediaDate = dateFormatter.string(from: creationDate)
        } else {
            mediaDate = "No date"
        }
    }
    
    // Modified function to go back to the previous media using history
    private func goBack() {
        if !previousIndices.isEmpty {
            // Get the most recent index
            let previousIndex = previousIndices.removeLast()
            currentIndex = previousIndex
            
            // Update UI for the new current index
            updateMediaSize()
            updateMediaDate()
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
    
    // Modified to load only first batch
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
                    
                    // Only load the first batch initially
                    let firstBatchSize = min(self.batchSize, fetchedMedia.count)
                    self.paginatedMediaItems = Array(fetchedMedia.prefix(firstBatchSize))
                    
                    self.updateMediaSize()
                    self.updateMediaDate()
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
                self.updateMediaDate()
                
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
            // Check if we need to load more from mediaItems
            if currentIndex >= paginatedMediaItems.count && currentIndex < mediaItems.count {
                // Instead of loading more, show the break view at batch boundaries
                checkForBreak()
            } else if currentIndex >= mediaItems.count && mediaItems.count > 0 {
                // Loop back to beginning
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
    }
    
    private func resetAndReload() {
        // Clean all caches
        preloadedPlayers.removeAllObjects()
        highQualityImageCache.removeAllObjects()
        lowQualityImageCache.removeAllObjects()
        
        // Reset history when looping back
        previousIndices = []
        
        // Reset batch counter
        currentBatch = 0
        
        // Reload paginated items and preload content
        let firstBatchSize = min(batchSize, mediaItems.count)
        paginatedMediaItems = Array(mediaItems.prefix(firstBatchSize))
        updateMediaSize()
        updateMediaDate()
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
    
    // Modified handleSwipe to track previous indices
    func handleSwipe(direction: SwipeDirection) {
        if currentIndex < paginatedMediaItems.count {
            let currentItem = paginatedMediaItems[currentIndex]
            
            switch direction {
            case .left:
                SwipedMediaManager.shared.addSwipedMedia(currentItem, toTrash: true)

            case .right:
                SwipedMediaManager.shared.addSwipedMedia(currentItem, toTrash: false)

            case .skip:
                // Don't trash, just move to next and add back to stack
                paginatedMediaItems.insert(currentItem, at: currentIndex + 3) // comes back in ~3 cards
            }
            
            previousIndices.append(currentIndex)
            if previousIndices.count > maxGoBackCount {
                previousIndices.removeFirst()
            }

            swipeCount += 1
            UserDefaults.standard.set(swipeCount, forKey: "swipeCount")
            
            let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            feedbackGenerator.impactOccurred()
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            offset.width = direction == .left ? -1000 : 1000
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            offset = .zero
            currentIndex += 1

            self.cleanupOldContent()
            self.preloadContentForCurrentIndex()
            self.checkForBreak()  // Check if we need to show break after swiping
        }
    }
    
    func updateMediaSize() {
        guard currentIndex < paginatedMediaItems.count else { return }
        _ = paginatedMediaItems[currentIndex]
        
        // Use MediaManager to get size or implement directly
        mediaSize = MediaManager.shared.updateMediaSize(for: paginatedMediaItems, index: currentIndex)
    }
    
    func handleAppReturnFromBackground() {
        print("App resumed from background. Reloading visible media...")

        // Refresh visible media
        updateMediaSize()
        updateMediaDate()
        preloadContentForCurrentIndex()
        pauseNonFocusedVideos()
    }
}

// Break View component
struct BreakView: View {
    let batchNumber: Int
    @Binding var isLoading: Bool
    let onContinue: () -> Void
    
    var body: some View {
        ZStack {
            // Dark overlay
            Color.black.opacity(0.85)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 25) {
                // Glowing title
                Text("Quick Break")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: Color.green.opacity(0.8), radius: 10)
                
                // Message without item count
                VStack(spacing: 15) {
                    Text("Great Progress!")
                        .font(.title2.bold())
                        .foregroundColor(.green)
                    
                    Text("Don't Forget To Review Your Trashed Items!")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(LinearGradient(
                                    gradient: Gradient(colors: [Color.green.opacity(0.8), Color.green.opacity(0.3)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ), lineWidth: 2)
                        )
                )
                .padding()
                
                // Continue button only
                Button(action: onContinue) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.title3)
                        }
                        
                        Text(isLoading ? "Loading" : "Continue")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.green.opacity(0.7), lineWidth: 2)
                            )
                    )
                }
                .foregroundColor(.white)
                .disabled(isLoading)
                .padding(.horizontal)
                .padding(.horizontal)
            }
            .padding()
            .frame(maxWidth: 400)
        }
    }
}
