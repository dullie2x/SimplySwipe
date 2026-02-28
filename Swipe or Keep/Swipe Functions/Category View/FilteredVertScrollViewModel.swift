//
//  FilteredVertScrollViewModel.swift

import SwiftUI
import Photos
import AVKit

// MARK: - Filter Type Enum
enum FilterType {
    case album(PHAssetCollection)
    case year(String)
    case category(Int)
}

// MARK: - Make FilterType usable as a sheet item
extension FilterType: Identifiable, Equatable {
    var id: String {
        switch self {
        case .album(let c):     return "album:\(c.localIdentifier)"
        case .year(let y):      return "year:\(y)"
        case .category(let i):  return "cat:\(i)"
        }
    }

    static func == (lhs: FilterType, rhs: FilterType) -> Bool {
        switch (lhs, rhs) {
        case (.year(let a), .year(let b)):         return a == b
        case (.category(let a), .category(let b)): return a == b
        case (.album(let a), .album(let b)):       return a.localIdentifier == b.localIdentifier
        default:                                   return false
        }
    }
}

@MainActor
class FilteredVertScrollViewModel: ObservableObject {
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
    @Published var currentAssetMuted = true
    
    // Gesture state
    @Published var dragOffset: CGFloat = 0
    @Published var horizontalOffset: CGFloat = 0
    @Published var isDragging = false
    @Published var gestureDirection: GestureDirection = .undecided
    
    // External data
    @Published var swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
    @ObservedObject var swipeData = SwipeData.shared
    
    // Filter options
    var filterOptions: PHFetchOptions
    
    // MARK: - Reset Functionality Properties
    var currentFilterType: FilterType?
    var currentCollection: PHAssetCollection?
    var currentYear: String?
    var currentCategoryIndex: Int?
    
    // Dependencies
    private let cacheManager = CacheManager.shared
    private var hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    // Configuration
    private let initialLoadSize = 20
    private let preloadWindow = 3  // OPTIMIZED: Reduced from 10 to 3 (current + 3 forward)
    private let maxBackwardNavigation = 12
    
    init(filterOptions: PHFetchOptions) {
        self.filterOptions = filterOptions
        hapticGenerator.prepare()
    }
    
    // MARK: - Enhanced Initializer with Filter Type
    convenience init(filterOptions: PHFetchOptions, filterType: FilterType) {
        self.init(filterOptions: filterOptions)
        self.currentFilterType = filterType
        
        // Store specific data for easy access
        switch filterType {
        case .album(let collection):
            self.currentCollection = collection
        case .year(let year):
            self.currentYear = year
        case .category(let index):
            self.currentCategoryIndex = index
        }
    }
    
    // MARK: - Reset Functions
    
    // Reset current album/year/category
    func resetCurrentFilter() {
        guard let filterType = currentFilterType else {
            return
        }
        
        switch filterType {
        case .album(let collection):
            SwipedMediaManager.shared.resetAlbum(collection)
        case .year(let year):
            SwipedMediaManager.shared.resetYear(year)
        case .category(let index):
            let category: SwipedMediaManager.MediaCategory
            switch index {
            case 0: category = .recents
            case 1: category = .screenshots
            case 2: category = .favorites
            default: return
            }
            SwipedMediaManager.shared.resetCategory(category)
        }
        
        // Navigate back to home after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.goToHome()
        }
    }
    
    // Get display name for confirmation dialog
    var filterDisplayName: String {
        guard let filterType = currentFilterType else { return "this collection" }
        
        switch filterType {
        case .album(let collection):
            return collection.localizedTitle ?? "this album"
        case .year(let year):
            return year
        case .category(let index):
            switch index {
            case 0: return "Recents"
            case 1: return "Screenshots"
            case 2: return "Favorites"
            default: return "this category"
            }
        }
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
            // Capture filterOptions on main actor
            let filterOptions = await MainActor.run { self.filterOptions }
            
            // Perform fetch on background thread
            let result = await Task.detached {
                PHAsset.fetchAssets(with: filterOptions)
            }.value
            
            var fetchedMedia: [PHAsset] = []
            
            autoreleasepool {
                result.enumerateObjects { asset, _, _ in
                    fetchedMedia.append(asset)
                }
            }
            
            await MainActor.run {
                if fetchedMedia.isEmpty {
                    self.isLoading = false
                    self.loadingProgress = 1.0
                    return
                }
                
                // NEW: Check if all items are already swiped before setting up pagination
                let swipedIdentifiers = SwipedMediaManager.shared.getSwipedMediaIdentifiers()
                let unswipedMedia = fetchedMedia.filter { !swipedIdentifiers.contains($0.localIdentifier) }
                
                if unswipedMedia.isEmpty {
                    // All items are swiped - go directly to empty state
                    self.mediaItems = fetchedMedia
                    self.totalMediaCount = fetchedMedia.count
                    self.paginatedMediaItems = []
                    self.unseenMediaItems = []
                    self.mediaTracker.removeAll()
                    self.previewIndex = 0
                    self.maxBackwardIndex = 0
                    self.seenMediaCount = fetchedMedia.count // All items have been seen
                    self.isLoading = false
                    self.loadingProgress = 1.0
                    return
                }
                
                // Continue with normal flow for collections with unswiped items
                self.mediaItems = fetchedMedia
                self.totalMediaCount = fetchedMedia.count
                self.mediaTracker.removeAll()
                
                // Use unswipedMedia for pagination instead of all media
                let initialBatch = Array(unswipedMedia.prefix(self.initialLoadSize))
                self.paginatedMediaItems = initialBatch
                
                // Initialize tracking for initial batch
                for item in initialBatch {
                    var tracker = MediaItemTracker(identifier: item.localIdentifier)
                    tracker.hasBeenSeen = false
                    self.mediaTracker[item.localIdentifier] = tracker
                }
                
                self.unseenMediaItems = Array(unswipedMedia.dropFirst(self.initialLoadSize))
                
                self.previewIndex = 0
                self.maxBackwardIndex = 0
                self.seenMediaCount = fetchedMedia.count - unswipedMedia.count // Count of already swiped items
                
                self.updateCurrentMedia()
                self.preloadInitialContent()
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
        
        let resources = PHAssetResource.assetResources(for: currentAsset)
        if let resource = resources.first {
            let size = resource.value(forKey: "fileSize") as? Int ?? 0
            mediaSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        } else {
            mediaSize = "Unknown"
        }
    }
    
    // MARK: - Cache Accessors
    func getPlayer(for index: Int) -> AVQueuePlayer? {
        guard let asset = safeAsset(at: index) else { return nil }
        return cacheManager.getPlayer(for: asset)
    }
    
    func getHighQualityImage(for index: Int) -> UIImage? {
        guard let asset = safeAsset(at: index) else { return nil }
        return cacheManager.getBestAvailableImage(for: asset)
    }
    
    func getLowQualityImage(for index: Int) -> UIImage? {
        guard let asset = safeAsset(at: index) else { return nil }
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

    func handleWindowPinchChanged(
        deltaScale: CGFloat,
        centroid: CGPoint,
        centroidDelta: CGPoint,
        cardSize: CGSize
    ) {
        let rawNew = zoomScale * deltaScale
        let clampedScale = max(1.0, min(5.0, rawNew))
        let effectiveDelta = clampedScale / zoomScale

        let cx = centroid.x - cardSize.width  / 2
        let cy = centroid.y - cardSize.height / 2

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isCurrentCardZoomed = false
        }
    }

    // MARK: - Drag Handling

    func handleDragChanged(value: DragGesture.Value, geometry: GeometryProxy, canSwipe: Bool) {
        // When zoomed, ignore drag — window pinch handles all pan-while-zoomed
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
                
                self.updateCurrentMedia()
            } else {
                // End of gallery reached
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
                // Swipe down → go back one
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
                // Swipe up → go forward one
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
    
    private func markCurrentAssetAsSeen() {
        guard let currentAsset = safeCurrentAsset() else { return }
        
        let id = currentAsset.localIdentifier
        
        // Update tracking - mark as seen but not swiped left/right
        var tracker = mediaTracker[id] ?? MediaItemTracker(identifier: id)
        tracker.hasBeenSeen = true
        tracker.lastViewedAt = Date()
        // Note: swipeDirection remains nil for vertical swipes (navigation only)
        // Note: isInTrash remains false for vertical swipes (no decision made)
        mediaTracker[id] = tracker
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
        
        // FIXED: Use ONLY preloadContentForCurrentIndex (progressive system)
        // Removed dual preload that was causing double downloads
        DispatchQueue.main.async {
            self.preloadContentForCurrentIndex()
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
        // Get currently swiped identifiers to filter them out
        let swipedIdentifiers = SwipedMediaManager.shared.getSwipedMediaIdentifiers()
        
        // Find unswiped items from the remaining media
        let itemsAlreadyLoaded = paginatedMediaItems.count
        let remainingItems = mediaItems.dropFirst(itemsAlreadyLoaded)
        let unswipedRemainingItems = remainingItems.filter { !swipedIdentifiers.contains($0.localIdentifier) }
        
        guard !unswipedRemainingItems.isEmpty else {
            return
        }
        
        let batchSize = 20
        let itemsToAdd = min(batchSize, unswipedRemainingItems.count)
        let nextItems = Array(unswipedRemainingItems.prefix(itemsToAdd))
        
        // Add to displayed items
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
        
        // Get all items that haven't been swiped yet for restart
        let swipedIdentifiers = SwipedMediaManager.shared.getSwipedMediaIdentifiers()
        let unswipedItems = mediaItems.filter { !swipedIdentifiers.contains($0.localIdentifier) }
        
        if unswipedItems.isEmpty {
            // If no unswiped items remain, use all items shuffled
            unseenMediaItems = mediaItems.shuffled()
        } else {
            // Use only unswiped items, shuffled
            unseenMediaItems = unswipedItems.shuffled()
        }
        
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
        NotificationCenter.default.post(name: .goHomeFromFiltered, object: nil)
    }
    
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
        // OPTIMIZED: Reduced preload range from ±10 to ±3
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
                // VIDEOS: Full quality for tiers 0-2, thumbnail for tier 3
                switch distance {
                case 0:
                    priority = .fullQuality  // Tier 0: Current video
                case 1, 2:
                    priority = .fullQuality  // Tier 1+2: Neighbors (prevents iCloud re-downloads)
                default:
                    priority = .thumbnail    // Tier 3: Far videos (poster only)
                }
            } else {
                // IMAGES: Preview quality is enough (loads fast)
                switch distance {
                case 0:
                    priority = .fullQuality  // Tier 0: Current image
                case 1, 2:
                    priority = .preview      // Tier 1+2: Screen-size preview (fast)
                default:
                    priority = .thumbnail    // Tier 3: Thumbnail only
                }
            }
            
            Task {
                cacheManager.preloadAssetProgressive(asset, at: idx, priority: priority)
            }
        }
    }

    // REMOVED: preloadImagesOnly() and preloadCurrentVideoOnly()
    // These were part of the OLD dual preload system - now using ONLY preloadContentForCurrentIndex()
    
    func cleanupOldContent() {
        guard let currentAsset = safeCurrentAsset() else { return }
        cacheManager.cleanup(around: currentAsset, window: preloadWindow)
    }
    
    // MARK: - Background/Foreground Handling
    
    func handleAppReturnFromBackground() {
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
