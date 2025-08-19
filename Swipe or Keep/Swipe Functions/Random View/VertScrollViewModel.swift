//
//  VertScrollViewModel.swift
//  Media App
//
//  Created on [Date]
//

import SwiftUI
import Photos
import AVKit

@MainActor
class VertScrollViewModel: ObservableObject {
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
    @ObservedObject var swipeData = SwipeData.shared
    
    // Dependencies
    private let cacheManager = CacheManager.shared
    private var hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    // Configuration
    private let initialLoadSize = 20
    private let preloadWindow = 10  // Increased from 5
    private let maxBackwardNavigation = 12
    
    
    
    init() {
        hapticGenerator.prepare()
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
        print("🔄 Resetting gesture state")
        isDragging = false
        gestureDirection = .undecided
        
        // Animate back to neutral position
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dragOffset = 0
            horizontalOffset = 0
        }
    }
    
    func forceResetGestureStateImmediate() {
        print("⚡ Force resetting gesture state immediately")
        isDragging = false
        gestureDirection = .undecided
        dragOffset = 0
        horizontalOffset = 0
    }
    
    // MARK: - Media Management
    func fetchMedia() {
        isLoading = true
        loadingProgress = 0.0
        
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
        
        updateMediaSize()
        updateMediaDate()
        
        // RESET: Every video starts muted
        currentAssetMuted = true
        
        // Set active player with TikTok-style behavior
        cacheManager.setActivePlayer(for: currentAsset, autoPlay: true)
        
        // Apply muted state for this asset
        if currentAsset.mediaType == .video {
            cacheManager.updateVolume(for: currentAsset, muted: true)
        }
        
        preloadContentForCurrentIndex()
        
        videoControlState.showControls = true
        videoControlState.resetControlsTimer {
            withAnimation {
                self.videoControlState.showControls = false
            }
        }
    }
    
    func updateMediaDate() {
        guard let asset = safeCurrentAsset() else {
            mediaDate = ""
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        
        if let creationDate = asset.creationDate {
            mediaDate = dateFormatter.string(from: creationDate)
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
        
        // Toggle mute state for current asset
        currentAssetMuted.toggle()
        
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
        
        print("🔊 Current asset mute state: \(!currentAssetMuted) → \(currentAssetMuted)")
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
    
    func handleDragChanged(value: DragGesture.Value, geometry: GeometryProxy, canSwipe: Bool) {
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
            horizontalOffset = 0
            dragOffset = value.translation.height
        case .undecided:
            break
        }
    }
    
    func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy, canSwipe: Bool) {
        switch gestureDirection {
        case .horizontal:
            handleHorizontalSwipeEnd(value: value, geometry: geometry, canSwipe: canSwipe)
        case .vertical:
            handleVerticalSwipeEnd(value: value, geometry: geometry)
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
        print("🚫 Drag gesture cancelled - resetting state")
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            resetGestureState()
        }
    }
    
    func handleHorizontalSwipeEnd(value: DragGesture.Value, geometry: GeometryProxy, canSwipe: Bool) {
        let threshold: CGFloat = geometry.size.width * 0.3
        
        print("🤏 Horizontal swipe: width=\(value.translation.width), threshold=\(threshold), canSwipe=\(canSwipe)")
        
        guard abs(value.translation.width) > threshold else {
            print("❌ Swipe failed: below threshold")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                horizontalOffset = 0
            }
            return
        }
        
        // Check if user can swipe - if not, show paywall
        guard canSwipe else {
            print("💳 No swipes remaining - showing paywall")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                horizontalOffset = 0
            }
            // Show the paywall
            showPaywall = true
            return
        }
        
        guard let currentAsset = safeCurrentAsset() else {
            print("❌ No current asset")
            return
        }
        
        let direction: SwipeDirection = value.translation.width > 0 ? .right : .left
        let id = currentAsset.localIdentifier
        
        print("✅ Processing swipe \(direction) for asset \(id)")
        
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
        
        // Animation and advancement
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let animationDir: CGFloat = direction == .right ? 1 : -1
        
        print("🎬 Starting animation: direction=\(animationDir)")
        
        withAnimation(.easeOut(duration: 0.3)) {
            horizontalOffset = animationDir * geometry.size.width * 1.5
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            print("📱 Advancing from index \(self.previewIndex)")
            self.horizontalOffset = 0
            if self.previewIndex < self.paginatedMediaItems.count - 1 {
                self.previewIndex += 1
                print("➡️ Advanced to index \(self.previewIndex)")
            } else {
                self.previewIndex = 0
                print("🔄 Wrapped to index 0")
            }
            self.updateCurrentMedia()
        }
    }
    
    func handleVerticalSwipeEnd(value: DragGesture.Value, geometry: GeometryProxy) {
        let threshold: CGFloat = geometry.size.height * 0.10

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            if value.translation.height > threshold {
                // swipe down → go back one
                if previewIndex > maxBackwardIndex {
                    let oldIndex = previewIndex
                    previewIndex -= 1
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
                    
                    // Update backward limit as we move forward
                    maxBackwardIndex = max(0, previewIndex - maxBackwardNavigation)
                    
                    // Ensure enough content is available
                    ensureEnoughContent()
                    
                    handleIndexChange(from: oldIndex, to: previewIndex)
                } else {
                    // At the very end - check if we've loaded everything
                    if paginatedMediaItems.count >= mediaItems.count {
                        // We're at the last item of all media - show end of gallery
                        print("🏁 At the end of all media - showing end of gallery")
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
        
        if let currentAsset = safeCurrentAsset(), currentAsset.mediaType == .video {
            // Cache manager now handles pausing neighbors automatically
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.preloadImagesOnly()
                self.preloadCurrentVideoOnly()
            }
        } else {
            DispatchQueue.main.async {
                self.preloadContentForCurrentIndex()
            }
        }
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

    
    func loadMoreContent() {
        // Simple check: do we have more items to load?
        let itemsAlreadyLoaded = paginatedMediaItems.count
        let totalItems = mediaItems.count
        
        guard itemsAlreadyLoaded < totalItems else {
            print("📥 All items already loaded")
            return
        }
        
        let batchSize = 20
        let itemsToAdd = min(batchSize, totalItems - itemsAlreadyLoaded)
        let startIndex = itemsAlreadyLoaded
        let endIndex = startIndex + itemsToAdd
        
        let nextItems = Array(mediaItems[startIndex..<endIndex])
        
        // Add to displayed items
        paginatedMediaItems.append(contentsOf: nextItems)
        
        print("📥 Added \(itemsToAdd) items. Total loaded: \(paginatedMediaItems.count)/\(totalItems)")
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
        print("🔄 Regular Restart: Total media items: \(mediaItems.count)")
        print("🔄 Regular Restart: Clearing \(mediaTracker.count) tracked items")
        
        // Clear ALL tracking data first
        mediaTracker.removeAll()
        
        // Shuffle and reset
        unseenMediaItems = mediaItems.shuffled()
        paginatedMediaItems = Array(unseenMediaItems.prefix(initialLoadSize))
        unseenMediaItems.removeFirst(min(initialLoadSize, unseenMediaItems.count))
        
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
        
        print("🔄 Regular Restart: New paginated count: \(paginatedMediaItems.count)")
        print("🔄 Regular Restart: New unseen count: \(unseenMediaItems.count)")
        print("🔄 Regular Restart: Reset tracking for \(mediaTracker.count) items")
        
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
            let currentPreloadWindow = preloadWindow
            
            let group = DispatchGroup()
            for (idx, asset) in currentPaginatedItems.prefix(currentPreloadWindow).enumerated() {
                group.enter()
                Task {
                    // Use progressive loading for initial content
                    let priority: CacheManager.LoadingStage = idx == 0 ? .fullQuality : .preview
                    self.cacheManager.preloadAssetProgressive(asset, at: idx, priority: priority)
                    
                    await MainActor.run {
                        self.loadingProgress = Double(idx + 1) / Double(min(currentPreloadWindow, currentPaginatedItems.count))
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                Task { @MainActor in
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
        }
    }

    func preloadContentForCurrentIndex() {
        let start = max(maxBackwardIndex, previewIndex - 1)
        let end = min(previewIndex + preloadWindow, paginatedMediaItems.count)
        
        // FIXED: Ensure start <= end to prevent range crash
        guard start < end else {
            print("⚠️ Invalid preload range: start=\(start), end=\(end)")
            return
        }
        
        for idx in start..<end {
            guard idx < paginatedMediaItems.count else { continue }
            let asset = paginatedMediaItems[idx]
            let distance = abs(idx - previewIndex)
            
            // Progressive loading based on distance
            let priority: CacheManager.LoadingStage
            switch distance {
            case 0:
                // Current asset: Load full quality
                priority = .fullQuality
            case 1...2:
                // Next/previous: Load preview quality
                priority = .preview
            default:
                // Distant: Load thumbnails only
                priority = .thumbnail
            }
            
            Task {
                cacheManager.preloadAssetProgressive(asset, at: idx, priority: priority)
            }
        }
    }

    func preloadImagesOnly() {
        guard paginatedMediaItems.indices.contains(previewIndex) else { return }

        let start = max(maxBackwardIndex, previewIndex - 1)
        let end = min(previewIndex + preloadWindow, paginatedMediaItems.count)

        // FIXED: Ensure start <= end to prevent range crash
        guard start < end else {
            print("⚠️ Invalid preload images range: start=\(start), end=\(end)")
            return
        }

        for idx in start..<end {
            let asset = paginatedMediaItems[idx]
            guard asset.mediaType == .image else { continue }

            Task {
                cacheManager.preloadAsset(asset, at: idx)
            }
        }
    }

    func preloadCurrentVideoOnly() {
        guard let currentAsset = safeCurrentAsset() else { return }

        if currentAsset.mediaType == .video {
            Task {
                cacheManager.preloadAsset(currentAsset, at: previewIndex)
            }
        }

        let nextIndex = previewIndex + 1
        if let nextAsset = safeAsset(at: nextIndex), nextAsset.mediaType == .video {
            Task {
                cacheManager.preloadAsset(nextAsset, at: nextIndex)
            }
        }
    }

    func cleanupOldContent() {
        guard let currentAsset = safeCurrentAsset() else { return }
        cacheManager.cleanup(around: currentAsset, window: preloadWindow)
    }
    
    // MARK: - TikTok-Style Background/Foreground Handling (FIXED)
    
    func handleAppReturnFromBackground() {
        print("📱 App returning from background")
        
        // CRITICAL: Reset any stuck gesture states FIRST
        forceResetGestureStateImmediate()
        

        // Let cache manager handle the complex resume logic
        cacheManager.handleAppBecameActive()
        
        // Update current media to ensure UI is in sync
        updateCurrentMedia()
        
        // Light cleanup to remove any stale content
        cleanupOldContent()
        
        // Continue preloading around current position
        preloadContentForCurrentIndex()
        
        print("✅ App returned from background - resume complete")
    }
    
    func handleAppWillEnterBackground() {
        print("📱 App entering background")
        
        // Reset gesture state to prevent stuck states
        forceResetGestureStateImmediate()
        
        // Clean up timers
        videoControlState.cleanup()
    }
}

