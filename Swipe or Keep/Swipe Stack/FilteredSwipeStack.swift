import SwiftUI
import Photos
import AVKit

struct FilteredSwipeStack: View {
    @State private var offset = CGSize.zero
    @State private var currentIndex = 0
    @State private var mediaItems: [PHAsset] = []
    @State private var paginatedMediaItems: [PHAsset] = []
    @State private var mediaSize: String = "0 MB"
    @State private var isLoading = true
    @State private var loadingProgress: Double = 0.0
    @State private var previousIndices: [Int] = []
    @State private var maxGoBackCount = 2
    @State private var mediaDate: String = ""
    @ObservedObject var swipeData = SwipeData.shared
    @State var showPaywall = false


    
    // Use NSCache instead of Dictionary for better memory management
    private let preloadedPlayers = NSCache<NSNumber, CachedPlayer>()
    private let highQualityImageCache = NSCache<NSNumber, UIImage>()
    private let lowQualityImageCache = NSCache<NSNumber, UIImage>()
    
    // Wrapper class for AVPlayer since NSCache requires reference types
    class CachedPlayer {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper?
        
        init(player: AVQueuePlayer, looper: AVPlayerLooper?) {
            self.player = player
            self.looper = looper
        }
    }
    
    @State private var swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
    @Environment(\.presentationMode) var presentationMode
    
    // Reduce the page size from 30 to 15 for better memory management
    private let pageSize = 20
    // Preload window - how many items to load ahead
    private let preloadWindow = 5
    
    var filterOptions: PHFetchOptions
    
    init(filterOptions: PHFetchOptions) {
        self.filterOptions = filterOptions
        
        // Configure caches with appropriate limits
        self.highQualityImageCache.countLimit = 10 // Only keep 5 high quality images in memory
        self.lowQualityImageCache.countLimit = 15 // Keep 10 thumbnails
        self.preloadedPlayers.countLimit = 5 // Only keep 3 video players in memory
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top inline navigation bar with smaller text
            HStack {
                // Back Button
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "arrow.left.circle")
                        .resizable()
                        .frame(width: 26, height: 26)
                        .foregroundColor(.white)
                }
                .padding(.leading, 10)
                
                if !isLoading && currentIndex < mediaItems.count {
                    Spacer()
                    
                    // Size text with smaller font
                    Text(mediaSize)
                        .font(Font.callout.weight(.bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .onChange(of: currentIndex) { _ in
                            updateMediaSize()
                            updateMediaDate()
                            preloadContentForCurrentIndex()
                            cleanupOldContent()
                        }
                    
                    Spacer()
                    
                    // Date display with smaller font
                    Text(mediaDate)
                        .font(Font.callout.weight(.bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                    
                    Spacer()
                    
                    // Share button
                    if currentIndex < paginatedMediaItems.count {
                        ShareButton(asset: paginatedMediaItems[currentIndex])
                            .frame(width: 36, height: 36)
                    }
                    
                    // Go back button - only enabled if there are previous indices
                    Button(action: goBack) {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(!previousIndices.isEmpty ? .green : .gray)
                    }
                    .disabled(previousIndices.isEmpty)
                    .padding(.horizontal, 4)
                    
                    // Counter with smaller font
                    Text("\(currentIndex + 1)/\(mediaItems.count)")
                        .font(Font.footnote.weight(.bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                } else {
                    Spacer()
                }
            }
            .padding(.vertical, 4)
            .background(Color.black)
            .zIndex(2)
            
            
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
                    }
                    .padding(30)
                    // Add a subtle animation
                    .scaleEffect(1.0)
                    .animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: UUID())
            
                } else if currentIndex >= mediaItems.count {
                    VStack {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 70))
                                .foregroundColor(.green)
                            
                            Text("All Done!")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        // Return to Home button
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Text("Return to Home")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(LinearGradient(
                                            gradient: Gradient(colors: [Color.green.opacity(0.7), Color.blue.opacity(0.7)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                )
                                .shadow(color: Color.green.opacity(0.3), radius: 5, x: 0, y: 2)
                        }
                        .padding(.top, 20)
                        
                    }
                } else {
                    GeometryReader { geometry in
                        ZStack {
                            // Only render at most 2 cards at a time to reduce memory
                            ForEach(currentIndex..<min(currentIndex + 2, paginatedMediaItems.count), id: \.self) { index in
                                if index < paginatedMediaItems.count {
                                    let canSwipe = SwipeData.shared.isPremium || SwipeData.shared.remainingSwipes() > 0

                                    FilteredMediaCardView(
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
                                    .gesture(
                                        DragGesture()
                                            .onChanged { gesture in
                                                if canSwipe && index == currentIndex {
                                                    offset = gesture.translation
                                                }
                                            }
                                            .onEnded { _ in
                                                if canSwipe && index == currentIndex {
                                                    handleSwipeEnd()
                                                } else if index == currentIndex {
                                                    handleSwipe(direction: .left) // Triggers paywall
                                                }
                                            }
                                    )
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
        .onAppear(perform: fetchFilteredMedia)
        .onAppear(perform: updateMediaDate)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            handleAppReturnFromBackground()
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallMaxView()
        }
        .navigationBarHidden(true)

    }
    
    // Function to update media date
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
    
    // Function to go back to the previous media
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
    
    func fetchFilteredMedia() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PHAsset.fetchAssets(with: filterOptions)
            var tempMediaItems: [PHAsset] = []
            
            // Use autoreleasepool to prevent memory buildup during enumeration
            autoreleasepool {
                result.enumerateObjects { asset, _, _ in
                    tempMediaItems.append(asset)
                }
            }
            
            DispatchQueue.main.async {
                if tempMediaItems.isEmpty {
                    self.isLoading = false
                    self.loadingProgress = 1.0
                    print("No media items found.")
                    return
                }
                
                // Start with just enough items for initial view
                self.mediaItems = tempMediaItems
                self.paginatedMediaItems = Array(tempMediaItems.prefix(self.pageSize))
                self.updateMediaSize()
                self.updateMediaDate()
                self.preloadInitialContent()
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
            }
        }
    }
    
    func preloadContentForCurrentIndex() {
        pauseNonFocusedVideos()
        
        // First, check if we're at or past the end
        guard currentIndex < paginatedMediaItems.count else { return }
        
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
        guard SwipeData.shared.isPremium || SwipeData.shared.remainingSwipes() > 0 else {
            // Show Paywall when out of swipes and not premium
            showPaywall = true
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }
        
        if currentIndex < paginatedMediaItems.count {
            let currentItem = paginatedMediaItems[currentIndex]
            
            switch direction {
            case .left:
                SwipedMediaManager.shared.addSwipedMedia(currentItem, toTrash: true)

            case .right:
                SwipedMediaManager.shared.addSwipedMedia(currentItem, toTrash: false)

            case .skip:
                paginatedMediaItems.insert(currentItem, at: currentIndex + 3)
            }
            
            // Save current index to goBack history
            previousIndices.append(currentIndex)
            if previousIndices.count > maxGoBackCount {
                previousIndices.removeFirst()
            }
            
            // Increment swipe count (respects premium + extra swipes)
            SwipeData.shared.incrementSwipeCount()
            
            // Haptic feedback
            let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            feedbackGenerator.prepare()
            feedbackGenerator.impactOccurred()
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            offset.width = direction == .left ? -1000 : 1000
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            offset = .zero
            currentIndex += 1
            cleanupOldContent()
            preloadContentForCurrentIndex()
        }
    }
    
    func handleSwipeEnd() {
        if offset.width > 100 {
            handleSwipe(direction: .right)
        } else if offset.width < -100 {
            handleSwipe(direction: .left)
        } else {
            withAnimation(.spring()) {
                offset = .zero
            }
        }
    }

    
    func updateMediaSize() {
        guard currentIndex < paginatedMediaItems.count else { return }
        let asset = paginatedMediaItems[currentIndex]
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            mediaSize = ByteCountFormatter.string(fromByteCount: Int64(resource.value(forKey: "fileSize") as? Int ?? 0), countStyle: .file)
        }
    }
    
    func handleAppReturnFromBackground() {
        print("App returned to foreground. Reloading current and nearby media...")

        // Reset loading flags just in case
        isLoading = false

        // Reload media size for current asset
        updateMediaSize()
        updateMediaDate()

        // Force preloading current and upcoming content
        preloadContentForCurrentIndex()
        pauseNonFocusedVideos()
    }

}
