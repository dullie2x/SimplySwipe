//
//  VertScrollViewModel.swift
//  Media App
//
//  Created on [Date]
//

import SwiftUI
import Photos
import AVKit
import Combine

@MainActor
class VertScrollViewModel: ObservableObject {
    // Static cached DateFormatter to avoid repeated allocations
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    // Core media data
    @Published var mediaItems: [PHAsset] = []
    @Published var paginatedMediaItems: [PHAsset] = []
    @Published var unseenMediaItems: [PHAsset] = []

    // Media tracking
    @Published var mediaTracker: [String: MediaItemTracker] = [:]
    
    // Index management
    @Published var previewIndex = 0
    @Published var maxBackwardIndex = 0
    
    // UI state
    @Published var mediaSize: String = "0 MB"
    @Published var mediaDate: String = ""
    @Published var isLoading = true
    @Published var loadingProgress: Double = 0.0
    @Published var showShareSheet = false
    @Published var showPaywall = false
    @Published var isCurrentCardZoomed: Bool = false

    // Zoom render state — transient (resets to 1x when fingers lift)
    @Published var zoomScale: CGFloat = 1.0
    @Published var zoomOffset: CGSize = .zero

    // End of gallery state
    @Published var showingEndOfGallery = false
    @Published var totalMediaCount = 0
    @Published var seenMediaCount = 0
    
    // Video controls
    @Published var videoControlState = VideoControlState()
    @Published var currentAssetMuted = true  // Current asset's mute state (starts muted)
    
    // Gesture state
    @Published var dragOffset: CGFloat = 0
    @Published var horizontalOffset: CGFloat = 0
    @Published var isDragging = false
    @Published var gestureDirection: GestureDirection = .undecided
    
    // External data
    @Published var swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
    let swipeData = SwipeData.shared
    private var swipeDataCancellable: AnyCancellable?
    
    // Dependencies
    private let cacheManager = CacheManager.shared
    private var hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    // Dwell detection: only upgrade to full quality if user pauses on an item
    private var dwellTask: Task<Void, Never>?
    // Tracks the last preheat window so we can stop caching evicted assets
    private var lastPreheatAssets: [PHAsset] = []
    
    // Configuration
    private let initialLoadSize = 20
    private let preloadWindow = 3  // OPTIMIZED: Reduced from 5 to 3 (current + 3 forward)

    // High-water mark: how many items from mediaItems have been pushed into paginatedMediaItems.
    // Must NOT use paginatedMediaItems.count because trimOldContent() shrinks that array
    // without consuming new items — using .count as an offset would replay already-seen assets.
    private var mediaLoadedOffset = 0
    private let maxBackwardNavigation = 12
    
    init() {
        hapticGenerator.prepare()

        // Forward SwipeData changes to this ViewModel's objectWillChange
        swipeDataCancellable = SwipeData.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }
    
    // MARK: - Safe Access Methods
    func safeAsset(at index: Int) -> PHAsset? {
        guard index >= 0 && index < paginatedMediaItems.count else { return nil }
        return paginatedMediaItems[index]
    }
    
    func safeCurrentAsset() -> PHAsset? {
        return safeAsset(at: previewIndex)
    }
    
    // MARK: - Gesture State Management
    
    func resetGestureState() {
        isDragging = false
        gestureDirection = .undecided
        
        // Animate back to neutral position
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = 0
            horizontalOffset = 0
        }
    }
    
    func forceResetGestureStateImmediate() {
        isDragging = false
        gestureDirection = .undecided
        dragOffset = 0
        horizontalOffset = 0
    }
    
    // MARK: - Media Management
    func fetchMedia() {
        isLoading = true
        loadingProgress = 0.0
        
        Task {
            // OPTIMIZED: For large libraries (10K+ assets), don't load everything at once
            // Instead, use lazy random sampling for better performance
            
            // Fetch total count first (fast)
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let result = await Task.detached {
                PHAsset.fetchAssets(with: fetchOptions)
            }.value
            
            let totalCount = result.count
            
            await MainActor.run {
                
                if totalCount == 0 {
                    self.isLoading = false
                    self.loadingProgress = 1.0
                    return
                }
                
                self.totalMediaCount = totalCount
                
                // OPTIMIZED: For large libraries (>5000), use lazy random access
                // For smaller libraries, load all and shuffle (original behavior)
                if totalCount > 5000 {
                    self.fetchMediaLazy(result: result, totalCount: totalCount)
                } else {
                    self.fetchMediaTraditional(result: result)
                }
            }
        }
    }
    
    // OPTIMIZED: Lazy random sampling for large libraries
    private func fetchMediaLazy(result: PHFetchResult<PHAsset>, totalCount: Int) {
        // Generate random indices
        var randomIndices = Set<Int>()
        while randomIndices.count < min(1000, totalCount) {  // Sample max 1000 random items
            randomIndices.insert(Int.random(in: 0..<totalCount))
        }
        
        // Fetch only the random samples
        var sampledAssets: [PHAsset] = []
        for index in randomIndices.sorted() {
            if index < totalCount {
                sampledAssets.append(result.object(at: index))
            }
        }
        
        // Shuffle the sampled assets
        sampledAssets.shuffle()

        // Filter out items the user has already swiped on in previous sessions
        let swipedIDs = SwipedMediaManager.shared.getSwipedMediaIdentifiers()
        let filteredAssets = sampledAssets.filter { !swipedIDs.contains($0.localIdentifier) }

        self.mediaItems = filteredAssets
        self.totalMediaCount = sampledAssets.count
        self.mediaTracker.removeAll()
        
        let initialBatch = Array(sampledAssets.prefix(self.initialLoadSize))
        self.paginatedMediaItems = initialBatch
        
        // Initialize tracking
        for item in initialBatch {
            var tracker = MediaItemTracker(identifier: item.localIdentifier)
            tracker.hasBeenSeen = false
            self.mediaTracker[item.localIdentifier] = tracker
        }
        
        self.unseenMediaItems = Array(sampledAssets.dropFirst(self.initialLoadSize))
        self.mediaLoadedOffset = initialBatch.count

        self.previewIndex = 0
        self.maxBackwardIndex = 0
        self.seenMediaCount = 0

        self.updateCurrentMedia()
        self.preloadInitialContent()
    }
    
    // Traditional: Load all assets (for smaller libraries)
    private func fetchMediaTraditional(result: PHFetchResult<PHAsset>) {
        DispatchQueue.global(qos: .userInitiated).async {
            MediaManager.shared.fetchMedia { fetchedMedia, _ in
                DispatchQueue.main.async {
                    if fetchedMedia.isEmpty {
                        self.isLoading = false
                        self.loadingProgress = 1.0
                        return
                    }
                    
                    self.mediaItems = fetchedMedia
                    self.totalMediaCount = fetchedMedia.count
                    self.mediaTracker.removeAll()
                    
                    let initialBatch = Array(fetchedMedia.prefix(self.initialLoadSize))
                    self.paginatedMediaItems = initialBatch
                    
                    // Initialize tracking for initial batch
                    for item in initialBatch {
                        var tracker = MediaItemTracker(identifier: item.localIdentifier)
                        tracker.hasBeenSeen = false
                        self.mediaTracker[item.localIdentifier] = tracker
                    }
                    
                    self.unseenMediaItems = Array(fetchedMedia.dropFirst(self.initialLoadSize))
                    self.mediaLoadedOffset = initialBatch.count

                    self.previewIndex = 0
                    self.maxBackwardIndex = 0
                    self.seenMediaCount = 0
                    
                    self.updateCurrentMedia()
                    self.preloadInitialContent()
                }
            }
        }
    }
    
    func updateCurrentMedia() {
        guard let currentAsset = safeCurrentAsset() else { return }

        // Always reset zoom when moving to a new card
        isCurrentCardZoomed = false
        zoomScale = 1.0
        zoomOffset = .zero

        // Update UI strings
        updateMediaSize()
        updateMediaDate()
        
        // Use global mute preference instead of always starting muted
        currentAssetMuted = VideoMutePreference.shared.isMuted
        
        // Set active player with TikTok-style behavior
        cacheManager.setActivePlayer(for: currentAsset, autoPlay: true)
        if currentAsset.mediaType == .video {
            cacheManager.updateVolume(for: currentAsset, muted: currentAssetMuted)
        }
        
        // ✅ Ensure the very first/just-shown card is counted as "seen" once.
        if mediaTracker[currentAsset.localIdentifier]?.hasBeenSeen != true {
            markCurrentAssetAsSeen()  // NOTE: your mark function does not bump swipeCount
        }
        
        // Preload neighbors
        preloadContentForCurrentIndex()
        
        // Controls timing
        videoControlState.showControls = true
        videoControlState.resetControlsTimer {
            withAnimation {
                self.videoControlState.showControls = false
            }
        }

        // Dwell detection: upgrade to full quality after 800ms if user hasn't swiped away
        dwellTask?.cancel()
        if let asset = safeCurrentAsset() {
            let capturedAsset = asset
            dwellTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
                guard !Task.isCancelled, let self else { return }
                self.cacheManager.upgradeToFullQuality(for: capturedAsset)
            }
        }
    }

    func updateMediaDate() {
        guard let asset = safeCurrentAsset() else {
            mediaDate = ""
            return
        }

        if let creationDate = asset.creationDate {
            mediaDate = Self.dateFormatter.string(from: creationDate)
        } else {
            mediaDate = "No date"
        }
    }
    
    func updateMediaSize() {
        guard let currentAsset = safeCurrentAsset() else {
            mediaSize = "0 MB"
            return
        }
        mediaSize = MediaManager.shared.updateMediaSize(for: [currentAsset], index: 0)
    }
    
    // MARK: - Cache Accessors
    func getPlayer(for index: Int) -> AVQueuePlayer? {
        guard let asset = safeAsset(at: index) else { return nil }
        return cacheManager.getPlayer(for: asset)
    }
    
    func getHighQualityImage(for index: Int) -> UIImage? {
        guard let asset = safeAsset(at: index) else { return nil }
        // Use progressive loading - gets best available quality
        return cacheManager.getBestAvailableImage(for: asset)
    }
    
    func getLowQualityImage(for index: Int) -> UIImage? {
        guard let asset = safeAsset(at: index) else { return nil }
        // For backward compatibility, also try progressive cache
        return cacheManager.getBestAvailableImage(for: asset) ?? cacheManager.getLowQualityImage(for: asset)
    }
    
    // MARK: - Video Control Methods
    func handleTap() {
        videoControlState.showControlsTemporarily {
            withAnimation {
                self.videoControlState.showControls = false
            }
        }
        
        // Toggle actual player state
        if let currentAsset = safeCurrentAsset(), currentAsset.mediaType == .video,
           let player = cacheManager.getPlayer(for: currentAsset) {
            if videoControlState.isPaused {
                player.play()
                videoControlState.isPaused = false
            } else {
                player.pause()
                videoControlState.isPaused = true
            }
        }
    }
    
    func toggleMute() {
        guard let currentAsset = safeCurrentAsset() else { return }
        
        // Toggle mute state for current asset AND update global preference
        currentAssetMuted.toggle()
        VideoMutePreference.shared.isMuted = currentAssetMuted
        
        // Handle audio session based on mute state
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            if currentAssetMuted {
                // Video is now muted - allow background music
                appDelegate.allowBackgroundMusic()
            } else {
                // Video is now unmuted - stop background music
                appDelegate.activateVideoPlayback()
            }
        }
        
        // Update current player volume
        if currentAsset.mediaType == .video {
            cacheManager.updateVolume(for: currentAsset, muted: currentAssetMuted)
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    // MARK: - Gesture Handling
    func determineGestureDirection(translation: CGSize) -> GestureDirection {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        let threshold: CGFloat = 15
        let ratio: CGFloat = 2.0
        
        if horizontal > threshold && horizontal > vertical * ratio {
            return .horizontal
        } else if vertical > threshold && vertical > horizontal * ratio {
            return .vertical
        }
        return .undecided
    }
    
    // MARK: - Zoom Handling (window-level pinch — transient, snaps back on lift)

    func handleWindowPinchBegan() {
        isCurrentCardZoomed = true
    }

    /// Called each frame during a pinch. Applies incremental scale anchored at the
    /// pinch centroid so the content zooms from where the fingers are.
    func handleWindowPinchChanged(
        deltaScale: CGFloat,
        centroid: CGPoint,
        centroidDelta: CGPoint,
        cardSize: CGSize
    ) {
        let rawNew = zoomScale * deltaScale
        let clampedScale = max(1.0, min(5.0, rawNew))
        let effectiveDelta = clampedScale / zoomScale   // actual applied delta after clamping

        // Centroid relative to card center (card fills the screen, so center ≈ cardSize/2)
        let cx = centroid.x - cardSize.width  / 2
        let cy = centroid.y - cardSize.height / 2

        // Offset adjustment to keep the point under the fingers visually fixed as scale changes
        let anchorDX = cx * zoomScale * (1 - effectiveDelta)
        let anchorDY = cy * zoomScale * (1 - effectiveDelta)

        zoomScale = clampedScale
        zoomOffset = CGSize(
            width:  zoomOffset.width  + anchorDX + centroidDelta.x,
            height: zoomOffset.height + anchorDY + centroidDelta.y
        )
    }

    func handleWindowPinchEnded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            zoomScale = 1.0
            zoomOffset = .zero
        }
        // Keep flag true briefly so handleDragEnded (which may fire in the same frame)
        // still sees isCurrentCardZoomed == true and skips the swipe action.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isCurrentCardZoomed = false
        }
    }

    // MARK: - Drag Handling

    func handleDragChanged(value: DragGesture.Value, geometry: GeometryProxy, canSwipe: Bool) {
        // When zoomed, ignore drag — the window pinch handles all pan-while-zoomed
        if isCurrentCardZoomed {
            return
        }

        let currentDirection = determineGestureDirection(translation: value.translation)

        if !isDragging {
            isDragging = true
            gestureDirection = currentDirection
        } else if gestureDirection == .undecided {
            gestureDirection = currentDirection
        }
        
        switch gestureDirection {
        case .horizontal:
            if canSwipe {
                horizontalOffset = value.translation.width
            }
            dragOffset = 0
        case .vertical:
            // Allow vertical dragging visually even if they can't complete the swipe
            // The paywall check happens in handleVerticalSwipeEnd
            horizontalOffset = 0
            dragOffset = value.translation.height
        case .undecided:
            break
        }
    }
    
    func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy, canSwipe: Bool) {
        // If user was zooming, don't process as a swipe
        if isCurrentCardZoomed {
            isDragging = false
            gestureDirection = .undecided
            return
        }

        switch gestureDirection {
        case .horizontal:
            handleHorizontalSwipeEnd(value: value, geometry: geometry, canSwipe: canSwipe)
        case .vertical:
            handleVerticalSwipeEnd(value: value, geometry: geometry, canSwipe: canSwipe)
        case .undecided:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                horizontalOffset = 0
                dragOffset = 0
            }
        }
        
        isDragging = false
        gestureDirection = .undecided
    }
    
    func handleDragCancelled() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            resetGestureState()
        }
    }
    
    func handleHorizontalSwipeEnd(value: DragGesture.Value, geometry: GeometryProxy, canSwipe: Bool) {
        let threshold: CGFloat = geometry.size.width * 0.3
        
        guard abs(value.translation.width) > threshold else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                horizontalOffset = 0
            }
            return
        }
        
        // Check if user can swipe - if not, show paywall
        guard canSwipe else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                horizontalOffset = 0
            }
            showPaywall = true
            return
        }
        
        guard let currentAsset = safeCurrentAsset() else {
            return
        }
        
        let direction: SwipeDirection = value.translation.width > 0 ? .right : .left
        let id = currentAsset.localIdentifier
        
        // Single state update
        var tracker = mediaTracker[id] ?? MediaItemTracker(identifier: id)
        tracker.swipeDirection = direction
        tracker.hasBeenSeen = true
        tracker.lastViewedAt = Date()
        tracker.isInTrash = (direction == .left)
        mediaTracker[id] = tracker
        
        // Tell external systems
        SwipedMediaManager.shared.addSwipedMedia(currentAsset, toTrash: direction == .left)
        swipeData.incrementSwipeCount()
        
        // Top off content early for smoothness when we're nearing the end
        ensureEnoughContent()
        
        // Animation and advancement
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let animationDir: CGFloat = direction == .right ? 1 : -1
        
        withAnimation(.easeOut(duration: 0.3)) {
            horizontalOffset = animationDir * geometry.size.width * 1.5
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.horizontalOffset = 0

            let didAdvance = self.advanceForwardOrEnd()
            if didAdvance {
                // Keep backward limit behavior consistent with vertical swipes
                self.maxBackwardIndex = max(0, self.previewIndex - self.maxBackwardNavigation)

                // Make sure there's always a buffer
                self.ensureEnoughContent()

                // Trim old items to keep the ZStack from growing unboundedly
                self.trimOldContent()

                self.updateCurrentMedia()
            }
        }
    }
    
    func handleVerticalSwipeEnd(value: DragGesture.Value, geometry: GeometryProxy, canSwipe: Bool) {
        let threshold: CGFloat = geometry.size.height * 0.10

        // Check for swipe attempts that would require consuming a swipe
        let willConsumeSwipe = abs(value.translation.height) > threshold
        
        // If this action will consume a swipe and user can't swipe, show paywall
        if willConsumeSwipe && !canSwipe {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                dragOffset = 0
            }
            showPaywall = true
            return
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            if value.translation.height > threshold {
                // swipe down → go back one
                if previewIndex > maxBackwardIndex {
                    let oldIndex = previewIndex
                    previewIndex -= 1
                    
                    // Mark current asset as seen and increment swipe count
                    markCurrentAssetAsSeen()
                    swipeData.incrementSwipeCount()
                    
                    handleIndexChange(from: oldIndex, to: previewIndex)
                } else {
                    // Hit the backward limit - double haptic + bounce
                    triggerBackwardLimitFeedback()
                }
            }
            else if value.translation.height < -threshold {
                // swipe up → go forward one
                if previewIndex < paginatedMediaItems.count - 1 {
                    let oldIndex = previewIndex
                    previewIndex += 1

                    // Mark current asset as seen and increment swipe count
                    markCurrentAssetAsSeen()
                    swipeData.incrementSwipeCount()

                    // Update backward limit as we move forward
                    maxBackwardIndex = max(0, previewIndex - maxBackwardNavigation)

                    // Ensure enough content is available
                    ensureEnoughContent()

                    // Trim old items to keep the ZStack from growing unboundedly
                    trimOldContent()

                    handleIndexChange(from: oldIndex, to: previewIndex)
                } else {
                    // At the very end - check if we've loaded everything
                    if paginatedMediaItems.count >= mediaItems.count {
                        showEndOfGallery()
                    } else {
                        // Try to load more content
                        ensureEnoughContent()
                    }
                }
            }
            dragOffset = 0
        }
    }
    
    // Add this helper function if it doesn't exist
    private func markCurrentAssetAsSeen() {
        guard let currentAsset = safeCurrentAsset() else { return }
        
        let id = currentAsset.localIdentifier
        
        // Update tracking - mark as seen but not swiped left/right
        var tracker = mediaTracker[id] ?? MediaItemTracker(identifier: id)
        tracker.hasBeenSeen = true
        tracker.lastViewedAt = Date()
        mediaTracker[id] = tracker
        
        // Add this line - let SwipedMediaManager filter it out
        SwipedMediaManager.shared.addSwipedMedia(currentAsset, toTrash: false)
        
    }
    
    func triggerBackwardLimitFeedback() {
        hapticGenerator.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.hapticGenerator.impactOccurred()
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            dragOffset = 30
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.dragOffset = 0
            }
        }
    }
    
    func handleIndexChange(from oldIndex: Int, to newIndex: Int) {
        updateCurrentMedia()
        // NOTE: Do NOT call preloadContentForCurrentIndex() here.
        // updateCurrentMedia() already calls it. Adding a second deferred call via
        // DispatchQueue.main.async was firing the preload twice per swipe, doubling
        // the number of concurrent PHImageManager requests (1435 loads for 139 swipes).
    }
    
    // MARK: - Content Management
    func ensureEnoughContent() {
        let preloadBuffer = 3
        guard previewIndex >= paginatedMediaItems.count - preloadBuffer else { return }
        
        // Only load more if there are items left to load
        if paginatedMediaItems.count < mediaItems.count {
            loadMoreContent()
        }
    }

    // MARK: - Sliding Window: Trim old items that are too far behind current position
    // This prevents paginatedMediaItems (and the ZStack) from growing unboundedly,
    // which would cause severe performance degradation and loading-circle freezes after
    // many swipes. We keep maxBackwardNavigation + 2 items behind the current index.
    func trimOldContent() {
        let keepBackward = maxBackwardNavigation + 2
        let trimCount = max(0, previewIndex - keepBackward)
        guard trimCount > 0 else { return }

        paginatedMediaItems.removeFirst(trimCount)
        previewIndex     -= trimCount
        maxBackwardIndex  = max(0, maxBackwardIndex - trimCount)

    }

    func loadMoreContent() {
        // Use mediaLoadedOffset (not paginatedMediaItems.count) so that trimOldContent()
        // shrinking the array never causes already-seen items to be reloaded.
        guard mediaLoadedOffset < mediaItems.count else { return }

        let batchSize = 20
        let itemsToAdd = min(batchSize, mediaItems.count - mediaLoadedOffset)
        let nextItems = Array(mediaItems[mediaLoadedOffset..<mediaLoadedOffset + itemsToAdd])

        mediaLoadedOffset += itemsToAdd
        paginatedMediaItems.append(contentsOf: nextItems)
    }
    
    func showEndOfGallery() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                self.showingEndOfGallery = true
            }
        }
    }
    
    func safeRemoveCurrentItem() -> Bool {
        guard safeCurrentAsset() != nil else { return false }
        
        let removedItem = paginatedMediaItems.remove(at: previewIndex)
        
        // Update tracking
        var tracker = mediaTracker[removedItem.localIdentifier] ?? MediaItemTracker(identifier: removedItem.localIdentifier)
        tracker.hasBeenSeen = true
        tracker.lastViewedAt = Date()
        mediaTracker[removedItem.localIdentifier] = tracker
        
        // Handle index adjustment safely
        if paginatedMediaItems.isEmpty {
            ensureEnoughContent()
            return !paginatedMediaItems.isEmpty
        } else if previewIndex >= paginatedMediaItems.count {
            previewIndex = max(0, paginatedMediaItems.count - 1)
        }
        
        return true
    }
    
    // MARK: - End of Gallery Actions
    func restartGallery() {
        
        // Clear ALL tracking data first
        mediaTracker.removeAll()
        
        // Shuffle and reset — rebuild mediaItems in the new shuffled order so that
        // mediaLoadedOffset stays consistent with mediaItems indexing.
        mediaItems = mediaItems.shuffled()
        paginatedMediaItems = Array(mediaItems.prefix(initialLoadSize))
        mediaLoadedOffset = paginatedMediaItems.count
        
        // Initialize tracking for ALL items as unseen
        for item in mediaItems {  // Reset ALL items, not just initial batch
            var tracker = MediaItemTracker(identifier: item.localIdentifier)
            tracker.hasBeenSeen = false
            tracker.swipeDirection = nil
            tracker.isInTrash = false
            tracker.lastViewedAt = nil
            mediaTracker[item.localIdentifier] = tracker
        }
        
        previewIndex = 0
        maxBackwardIndex = 0
        seenMediaCount = 0
        
        withAnimation {
            showingEndOfGallery = false
        }
        
        updateCurrentMedia()
        preloadContentForCurrentIndex()
    }

    func shuffleAndRestart() {
        restartGallery()
    }

    func goToHome() {
        showingEndOfGallery = false
        NotificationCenter.default.post(name: .navigateToMainTab, object: nil)
    }
    
    // MARK: - Preloading and Audio
//    func initializeAudioSession() {
//        let audioSession = AVAudioSession.sharedInstance()
//        do {
//            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
//            try audioSession.setActive(true)
//        } catch {
//            print("Failed to set audio session: \(error)")
//        }
//    }
    
    func preloadInitialContent() {
        Task {
            let currentPaginatedItems = paginatedMediaItems
            
            // OPTIMIZED: Load ONLY the first item before showing UI
            if let firstAsset = currentPaginatedItems.first {
                // Load first item with full quality (fast path)
                await MainActor.run {
                    self.loadingProgress = 0.5
                }
                
                self.cacheManager.preloadAssetProgressive(firstAsset, at: 0, priority: .fullQuality)
                
                // Show UI immediately after first item starts loading
                await MainActor.run {
                    self.loadingProgress = 1.0
                    self.isLoading = false
                    
                    // Auto-play through cache manager (TikTok style)
                    if let firstAsset = self.safeAsset(at: self.previewIndex) {
                        self.cacheManager.setActivePlayer(for: firstAsset, autoPlay: true)
                    }
                    
                    self.videoControlState.resetControlsTimer {
                        withAnimation {
                            self.videoControlState.showControls = false
                        }
                    }
                }
            }
            
            // BACKGROUND: Preload the next items after UI is shown
            Task.detached(priority: .userInitiated) {
                // Preload items 1-4 (immediate neighbors)
                // Use preview quality for faster loads (full quality loads on-demand when viewed)
                for idx in 1..<min(5, currentPaginatedItems.count) {
                    let asset = currentPaginatedItems[idx]
                    // Videos get preview, images get preview (faster than full quality)
                    await self.cacheManager.preloadAssetProgressive(asset, at: idx, priority: .preview)
                }
                
                // Preload items 5-9 (further items) with thumbnail quality only
                if currentPaginatedItems.count > 5 {
                    for idx in 5..<min(10, currentPaginatedItems.count) {
                        let asset = currentPaginatedItems[idx]
                        await self.cacheManager.preloadAssetProgressive(asset, at: idx, priority: .thumbnail)
                    }
                }
            }
        }
    }

    func preloadContentForCurrentIndex() {
        // OPTIMIZED: Reduced preload range to ±3 (window=3)
        // Bidirectional: load 2 back, current, 3 forward = 6 items total
        let start = max(maxBackwardIndex, previewIndex - 2)  // 2 back for smooth reverse nav
        let end = min(previewIndex + preloadWindow + 1, paginatedMediaItems.count)  // +1 to include current
        
        guard start < end else {
            return
        }
        
        for idx in start..<end {
            guard idx < paginatedMediaItems.count else { continue }
            let asset = paginatedMediaItems[idx]
            let distance = abs(idx - previewIndex)
            
            // OPTIMIZED: Tier-based preloading
            // Tier 0: Current (distance 0)
            // Tier 1: ±1 (distance 1)
            // Tier 2: ±2 (distance 2)
            // Tier 3: +3 forward only (distance 3+)
            let priority: CacheManager.LoadingStage
            
            if asset.mediaType == .video {
                switch distance {
                case 0, 1:
                    priority = .fullQuality  // Current + ±1: Buffer video for instant playback
                default:
                    priority = .thumbnail    // Further: poster frame only
                }
            } else {
                switch distance {
                case 0:
                    priority = .preview      // Current image: fast degraded via .opportunistic (dwell will upgrade)
                case 1:
                    priority = .preview      // ±1: Screen-size preview
                default:
                    priority = .thumbnail    // Further: thumbnail only
                }
            }
            
            Task {
                cacheManager.preloadAssetProgressive(asset, at: idx, priority: priority)
            }
        }

        // Preheat thumbnails for the next 15 items using PHCachingImageManager.
        // This is cheap (system-level I/O coalescing) and eliminates pop-in for fast swipers.
        let preheatEnd = min(previewIndex + 16, paginatedMediaItems.count)
        if preheatEnd > previewIndex {
            let newPreheatAssets = Array(paginatedMediaItems[previewIndex..<preheatEnd])

            // Stop caching assets that fell out of the window
            let newIDs = Set(newPreheatAssets.map { $0.localIdentifier })
            let evicted = lastPreheatAssets.filter { !newIDs.contains($0.localIdentifier) }
            if !evicted.isEmpty {
                cacheManager.stopPreheatingThumbnails(for: evicted)
            }

            cacheManager.preheatThumbnails(for: newPreheatAssets)
            lastPreheatAssets = newPreheatAssets
        }
    }

    // REMOVED: preloadImagesOnly() and preloadCurrentVideoOnly()
    // These were part of the OLD dual preload system - now using ONLY preloadContentForCurrentIndex()
    
    func cleanupOldContent() {
        guard let currentAsset = safeCurrentAsset() else { return }
        cacheManager.cleanup(around: currentAsset, window: preloadWindow)
    }
    
    // MARK: - TikTok-Style Background/Foreground Handling (FIXED)
    
    func handleAppReturnFromBackground() {
        // CRITICAL: Reset any stuck gesture states immediately on main thread
        forceResetGestureStateImmediate()

        // Update UI synchronously — fast, must stay on main thread
        updateCurrentMedia()

        // Check for daily swipe reset in case the day rolled over while in background
        SwipeData.shared.resetIfNeeded()

        // Defer the heavy work so the scene transition completes first,
        // preventing the 0x8BADF00D watchdog from killing the app
        Task {
            cacheManager.handleAppBecameActive()
            await MainActor.run {
                cleanupOldContent()
                preloadContentForCurrentIndex()
            }
        }
    }
    
    func handleAppWillEnterBackground() {
        // Reset gesture state to prevent stuck states
        forceResetGestureStateImmediate()
        
        // Clean up timers
        videoControlState.cleanup()
    }
    
    // MARK: - Advance Helper (prevents wrap & pages content)
    @discardableResult
    private func advanceForwardOrEnd() -> Bool {
        // If not at the end of what's already loaded, just move forward
        if previewIndex < paginatedMediaItems.count - 1 {
            previewIndex += 1
            return true
        }

        // At the last loaded item — try to load more
        ensureEnoughContent()

        // If loading added items, advance into them
        if previewIndex < paginatedMediaItems.count - 1 {
            previewIndex += 1
            return true
        }

        // Nothing more to load: we've reached the end of all media
        if paginatedMediaItems.count >= mediaItems.count {
            showEndOfGallery()
        }
        return false
    }
}
