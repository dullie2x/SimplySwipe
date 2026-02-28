//
//  CacheManager.swift
//  Media App
//
//  Created on [Date]
//

import SwiftUI
import Photos
import AVKit
import Combine

// MARK: - Loading State
enum MediaLoadingState: Equatable {
    case loading
    case loaded
    case error(Error)
    case networkError
    case timeoutError

    static func == (lhs: MediaLoadingState, rhs: MediaLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading),
             (.loaded, .loaded),
             (.networkError, .networkError),
             (.timeoutError, .timeoutError):
            return true
        case (.error(let a), .error(let b)):
            return (a as NSError) == (b as NSError)
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .loading: return "Loading media..."
        case .loaded: return "Ready"
        case .error: return "Unable to load"
        case .networkError: return "Connection issue"
        case .timeoutError: return "Taking too long"
        }
    }

    var systemImageName: String {
        switch self {
        case .loading: return "arrow.triangle.2.circlepath"
        case .loaded: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        case .networkError: return "wifi.slash"
        case .timeoutError: return "clock"
        }
    }
}

struct MediaItemState {
    let loadingState: MediaLoadingState
    let loadAttempts: Int
    let maxRetryAttempts: Int = 3
    var canRetry: Bool { loadAttempts < maxRetryAttempts }
}

// MARK: - Player Wrapper (Simplified)
final class CachedPlayer {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(playerItem: AVPlayerItem) {
        // Start with an empty queue — AVPlayerLooper manages the queue entirely.
        // DO NOT use AVQueuePlayer(playerItem:) here; that creates a conflict where
        // the item is both directly in the queue AND used as the looper's template.
        let queue = AVQueuePlayer()
        queue.automaticallyWaitsToMinimizeStalling = true
        queue.volume = VideoMutePreference.shared.isMuted ? 0 : 1
        self.player = queue
        self.looper = AVPlayerLooper(player: queue, templateItem: playerItem)
    }

    func cleanup() {
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    deinit { cleanup() }
}

// MARK: - Unified Cache Manager (Simplified)
@MainActor
final class CacheManager: ObservableObject {
    static let shared = CacheManager()

    // MARK: - Core Caches
    private let preloadedPlayers = NSCache<NSString, CachedPlayer>()
    private let highQualityImageCache = NSCache<NSString, UIImage>()
    private let lowQualityImageCache = NSCache<NSString, UIImage>()

    // PHCachingImageManager for system-level thumbnail preheating
    private let cachingImageManager = PHCachingImageManager()
    
    // MARK: - Progressive Loading Caches
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let previewCache = NSCache<NSString, UIImage>()
    private let fullQualityCache = NSCache<NSString, UIImage>()
    
    // MARK: - Eviction Tracking (for debugging and optimization)
    private var evictionLog: [EvictionEvent] = []
    private let maxEvictionLogSize = 100  // Keep last 100 evictions
    
    struct EvictionEvent {
        let assetID: String
        let cacheType: String
        let timestamp: Date
        let memoryAtEviction: Int  // MB
        let reason: String
    }
    
    // MARK: - Telemetry Tracking
    private var telemetry = CacheTelemetry()
    
    struct CacheTelemetry {
        // Load metrics
        var videoLoadsStarted: Int = 0
        var videoLoadsCompleted: Int = 0
        var videoLoadsFailed: Int = 0
        var imageLoadsStarted: Int = 0
        var imageLoadsCompleted: Int = 0
        var imageLoadsFailed: Int = 0
        
        // Timing metrics
        var videoLoadTimes: [TimeInterval] = []
        var imageLoadTimes: [TimeInterval] = []
        var posterLoadTimes: [TimeInterval] = []
        
        // Cache metrics
        var cacheHits: Int = 0
        var cacheMisses: Int = 0
        var evictionCount: Int = 0
        var memoryWarnings: Int = 0
        
        // Memory metrics
        var peakMemoryMB: Int = 0
        var averageMemoryMB: Int = 0
        var memorySamples: [Int] = []
        
        // iCloud metrics
        var iCloudDownloadsStarted: Int = 0
        var iCloudDownloadsCompleted: Int = 0
        var iCloudDownloadsFailed: Int = 0
        var iCloudDownloadTimes: [TimeInterval] = []
        
        // Session info
        var sessionStartTime: Date = Date()
        var totalSwipes: Int = 0
        
        // Computed properties
        var videoLoadSuccessRate: Double {
            guard videoLoadsStarted > 0 else { return 0 }
            return Double(videoLoadsCompleted) / Double(videoLoadsStarted)
        }
        
        var imageLoadSuccessRate: Double {
            guard imageLoadsStarted > 0 else { return 0 }
            return Double(imageLoadsCompleted) / Double(imageLoadsStarted)
        }
        
        var cacheHitRate: Double {
            let total = cacheHits + cacheMisses
            guard total > 0 else { return 0 }
            return Double(cacheHits) / Double(total)
        }
        
        var avgVideoLoadTime: Double {
            guard !videoLoadTimes.isEmpty else { return 0 }
            return videoLoadTimes.reduce(0, +) / Double(videoLoadTimes.count)
        }
        
        var avgImageLoadTime: Double {
            guard !imageLoadTimes.isEmpty else { return 0 }
            return imageLoadTimes.reduce(0, +) / Double(imageLoadTimes.count)
        }
        
        var avgPosterLoadTime: Double {
            guard !posterLoadTimes.isEmpty else { return 0 }
            return posterLoadTimes.reduce(0, +) / Double(posterLoadTimes.count)
        }
        
        var sessionDuration: TimeInterval {
            return Date().timeIntervalSince(sessionStartTime)
        }
    }

    // MARK: - Memory Management
    // OPTIMIZED: Reduced from 800MB to 250MB for better stability and battery life
    private let maxTotalMemoryMB: Int = 250
    private var currentMemoryUsageMB: Int = 0

    // MARK: - State Management
    @Published var mediaStates: [String: MediaItemState] = [:]

    // Track all keys inserted into the progressive caches so getAllCachedKeys() works correctly
    private var progressiveCacheKeys: Set<String> = []
    private(set) var currentFocusedAssetID: String?
    private var pinnedPlayersStore: [String: CachedPlayer] = [:]
    
    // MARK: - Predictive Preloading State
    private var lastIndexChangeTime: Date?
    private var lastIndex: Int?
    private var scrollVelocity: Double = 0.0  // items per second
    private let velocitySmoothing: Double = 0.3  // Smoothing factor
    
    // Background state tracking (simplified)
    private var wasBackgrounded: Bool = false
    private var userPausedStates: [String: Bool] = [:]

    private var lastMemoryCheckTime: Date = .distantPast

    // Optional index↔︎assetID mapping
    private var indexToAssetID: [Int: String] = [:]
    private var assetIDToIndex: [String: Int] = [:]

    // MARK: - Task Management
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    private var timeoutTasks: [String: DispatchWorkItem] = [:]
    private var highQualityTasks: [String: Task<Void, Never>] = [:]

    // Stores in-flight PHImageManager request IDs keyed by cache key (e.g. "assetID_thumb").
    // Required for real cancellation — Task.cancel() sets a flag but doesn't stop an
    // in-flight PHImageManager request. Calling cancelImageRequest() makes PHImageManager
    // fire the callback immediately with nil, which resumes the continuation and lets the
    // guard !Task.isCancelled checks exit the load chain right away.
    private var imageRequestIDs: [String: PHImageRequestID] = [:]

    private let timeoutDuration: TimeInterval = 2.0  // Reduced timeout

    private init() {
        setupCacheLimits()
        
        // Listen for app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // ADDED: Listen for tab switch cleanup requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTabSwitchCleanup),
            name: .cleanupOldTabResources,
            object: nil
        )
    }
    
    private func setupCacheLimits() {
        // FIX: Reduced cache limits to stay under the 250MB budget.
        // All insertions now provide a byte-size cost so totalCostLimit actually evicts.
        // Previously every setObject() used cost=0, making totalCostLimit a no-op.

        // Progressive cache limits
        // Thumbnails: 200×200 @ 4 bytes = ~160KB each → 8 items ≈ 1.3MB
        thumbnailCache.countLimit = 8
        thumbnailCache.totalCostLimit = 8 * 1024 * 1024   // 8MB hard cap

        // Previews: screen-size @ 3x ≈ 11MB each → 5 items ≈ 55MB
        previewCache.countLimit = 5
        previewCache.totalCostLimit = 60 * 1024 * 1024    // 60MB hard cap

        // Full quality: same screen-size cap → 3 items ≈ 33MB
        // (was PHImageManagerMaximumSize — could be 100-190MB per image on modern iPhones!)
        fullQualityCache.countLimit = 3
        fullQualityCache.totalCostLimit = 40 * 1024 * 1024 // 40MB hard cap

        // Traditional cache limits (for videos and legacy image path)
        // Video players are expensive (50-100MB each) — keep only 3
        preloadedPlayers.countLimit = 3
        highQualityImageCache.countLimit = 5     // legacy path; not primary anymore
        lowQualityImageCache.countLimit = 8      // thumbnails for fallback display

        // Set memory limits — now effective because insertions provide costs
        let memoryLimit = maxTotalMemoryMB * 1024 * 1024  // 250MB
        preloadedPlayers.totalCostLimit = memoryLimit / 3      // ~83MB for videos
        highQualityImageCache.totalCostLimit = memoryLimit / 8  // ~31MB for legacy HQ
        lowQualityImageCache.totalCostLimit = memoryLimit / 16  // ~15MB for legacy LQ

        // Total hard-cap budget summary:
        //   thumbnails:    8MB
        //   previews:     60MB
        //   full quality: 40MB
        //   players:      83MB
        //   legacy HQ:    31MB
        //   legacy LQ:    15MB
        //   ─────────────────
        //   max possible: ~237MB  ✅ under 250MB
    }
    
    @objc private func handleMemoryWarning() {
        telemetry.memoryWarnings += 1
        aggressiveCleanup()
    }
    
    // ADDED: Handle tab switch cleanup
    @objc private func handleTabSwitchCleanup() {
        moderateCleanup()
    }
    
    private func moderateCleanup() {
        // Keep focused asset and neighbors, but clean up everything else
        guard let focusedID = currentFocusedAssetID,
              let focusedIndex = assetIDToIndex[focusedID] else {
            aggressiveCleanup()
            return
        }
        
        // Keep current asset and 1 neighbor on each side (reduced from 2)
        let keepRange = (focusedIndex - 1)...(focusedIndex + 1)
        var keepAssetIDs: Set<String> = [focusedID]
        
        for idx in keepRange {
            if let assetID = indexToAssetID[idx] {
                keepAssetIDs.insert(assetID)
            }
        }
        
        
        // Clean up everything outside this range
        cleanupExcept(keepAssetIDs)
        
        // Force clear progressive caches too
        clearProgressiveCachesExcept(focusedID)
    }
    
    private func trimCachesToHalfCapacity() {
        // Temporarily halve the count limits; NSCache's internal LRU eviction
        // will immediately purge the least-recently-used entries down to the new limit.
        // We then restore limits so future inserts aren't permanently capped.
        let originalThumbnail   = thumbnailCache.countLimit
        let originalPreview     = previewCache.countLimit
        let originalFullQuality = fullQualityCache.countLimit

        thumbnailCache.countLimit   = max(1, originalThumbnail   / 2)
        previewCache.countLimit     = max(1, originalPreview     / 2)
        fullQualityCache.countLimit = max(1, originalFullQuality / 2)

        // Restore limits on the next run loop tick (after eviction has occurred)
        DispatchQueue.main.async { [weak self] in
            self?.thumbnailCache.countLimit   = originalThumbnail
            self?.previewCache.countLimit     = originalPreview
            self?.fullQualityCache.countLimit = originalFullQuality
        }
    }
    
    private func aggressiveCleanup() {
        cachingImageManager.stopCachingImagesForAllAssets()

        // Keep only the focused asset and immediate neighbors
        guard let focusedID = currentFocusedAssetID,
              let focusedIndex = assetIDToIndex[focusedID] else {
            clearAll()
            return
        }
        
        let keepRange = (focusedIndex - 1)...(focusedIndex + 1)
        var keepAssetIDs: Set<String> = [focusedID]
        
        for idx in keepRange {
            if let assetID = indexToAssetID[idx] {
                keepAssetIDs.insert(assetID)
            }
        }
        
        cleanupExcept(keepAssetIDs)
        
        // Clear progressive caches except for current asset
        clearProgressiveCachesExcept(focusedID)
    }
    
    private func cleanupExcept(_ keepAssetIDs: Set<String>) {
        var cleanedPlayers = 0
        var cleanedImages = 0
        
        // Cleanup pinned players first
        for (assetID, cached) in pinnedPlayersStore where !keepAssetIDs.contains(assetID) {
            cached.cleanup()
            pinnedPlayersStore.removeValue(forKey: assetID)
            cleanedPlayers += 1
            logEviction(assetID: assetID, cacheType: "pinnedPlayer", reason: "cleanupExcept")
        }
        
        // Cleanup states and cached items
        for assetID in mediaStates.keys where !keepAssetIDs.contains(assetID) {
            if let cached = preloadedPlayers.object(forKey: assetID as NSString) {
                cached.cleanup()
                cleanedPlayers += 1
                logEviction(assetID: assetID, cacheType: "player", reason: "cleanupExcept")
            }
            preloadedPlayers.removeObject(forKey: assetID as NSString)
            highQualityImageCache.removeObject(forKey: assetID as NSString)
            lowQualityImageCache.removeObject(forKey: assetID as NSString)
            cleanedImages += 1
            mediaStates[assetID] = nil
            cancelTasks(for: assetID)
        }
        
        // CRITICAL: Also clear items that might be in NSCache but not in mediaStates
        // This is a brute force approach since NSCache doesn't expose its keys
        // We'll rely on the countLimit to handle this, but let's also clear all if needed
        
        
        // CRITICAL: If still over budget after cleaning, force clear ALL caches except pinned
        let currentMB = Int(getMemoryUsed() / 1_000_000)
        if currentMB > maxTotalMemoryMB {
            // Clear progressive caches more aggressively
            thumbnailCache.removeAllObjects()
            previewCache.removeAllObjects()
            logEviction(assetID: "multiple", cacheType: "thumbnails+previews", reason: "memoryPressure:\(currentMB)MB")
            // Keep full quality only for focused asset
        }
    }
    
    private func clearProgressiveCachesExcept(_ focusedAssetID: String) {
        // This would need to be implemented to selectively clear progressive caches
        // For now, clear everything except focused asset
        
        // Keep thumbnails (they're small)
        // Clear preview cache except focused
        // Clear full quality cache except focused
        
        let allKeys = getAllCachedKeys()
        for key in allKeys {
            if !key.contains(focusedAssetID) {
                previewCache.removeObject(forKey: key as NSString)
                fullQualityCache.removeObject(forKey: key as NSString)
            }
        }
    }
    
    // MARK: - Memory Monitoring

    /// Get current memory footprint in bytes.
    ///
    /// Uses `phys_footprint` from TASK_VM_INFO — the same metric Xcode's memory gauge
    /// and the iOS OOM killer use. This counts only pages your process has dirtied,
    /// excluding shared read-only framework code and memory-mapped photo data held by
    /// PHImageManager. The old `resident_size` from MACH_TASK_BASIC_INFO was ~2× higher,
    /// causing `checkMemoryBudget()` to fire aggressively and wipe caches unnecessarily.
    private func getMemoryUsed() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.phys_footprint : 0
    }
    
    /// Check if memory budget is exceeded and cleanup if needed
    func checkMemoryBudget() {
        let now = Date()
        guard now.timeIntervalSince(lastMemoryCheckTime) >= 2.0 else { return }
        lastMemoryCheckTime = now

        let usedMemory = getMemoryUsed()
        let usedMB = Int(usedMemory / 1_000_000)
        
        // Update tracked usage
        currentMemoryUsageMB = usedMB
        
        // Update telemetry
        telemetry.memorySamples.append(usedMB)
        if usedMB > telemetry.peakMemoryMB {
            telemetry.peakMemoryMB = usedMB
        }
        
        // Keep only last 100 samples
        if telemetry.memorySamples.count > 100 {
            telemetry.memorySamples.removeFirst()
        }
        
        telemetry.averageMemoryMB = telemetry.memorySamples.reduce(0, +) / max(1, telemetry.memorySamples.count)
        
        // FIX: Thresholds were way too high (375-400MB), causing runaway memory.
        // Budget is 250MB — aggressive cleanup at 300MB, moderate at 250MB, trim at 200MB.

        // CRITICAL: If 20% over budget, do aggressive cleanup
        if usedMB > (maxTotalMemoryMB + 50) {  // >300MB
            aggressiveCleanup()
        }
        // At budget, trigger moderate cleanup
        else if usedMB > maxTotalMemoryMB {     // >250MB
            moderateCleanup()
        }
        // At 80% capacity, proactively start trimming
        else if usedMB > (maxTotalMemoryMB * 80 / 100) {  // >200MB
            trimCachesToHalfCapacity()
        }
    }
    
    /// Get formatted memory usage string for debugging
    func getMemoryUsageString() -> String {
        let usedMB = Int(getMemoryUsed() / 1_000_000)
        return "\(usedMB)MB / \(maxTotalMemoryMB)MB"
    }
    
    private func getAllCachedKeys() -> [String] {
        return Array(progressiveCacheKeys)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Background Handling (Simplified)

    @objc private func appWillResignActive() {
        wasBackgrounded = true
        
        // Save current user pause states
        for (assetID, cachedPlayer) in pinnedPlayersStore {
            userPausedStates[assetID] = (cachedPlayer.player.timeControlStatus != .playing)
        }
        
        // Pause all players
        for (_, cached) in pinnedPlayersStore {
            cached.player.volume = 0.0
            cached.player.pause()
        }
        
        for assetID in mediaStates.keys {
            if let cached = preloadedPlayers.object(forKey: assetID as NSString) {
                cached.player.volume = 0.0
                cached.player.pause()
            }
        }
    }

    func handleAppBecameActive() {
        guard wasBackgrounded else { return }
        wasBackgrounded = false
        
        // Re-establish audio session first (silent fail — not critical)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        // Simple approach: just restart the focused player
        if let focusedID = currentFocusedAssetID,
           let cached = pinnedPlayersStore[focusedID],
           userPausedStates[focusedID] != true {
            
            // Small delay to ensure everything is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Simple seek to current time to refresh the render pipeline
                let currentTime = cached.player.currentTime()
                cached.player.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    cached.player.volume = 1.0
                    cached.player.play()
                }
            }
        }
        
        // Clear saved pause states
        userPausedStates.removeAll()
    }

    // MARK: - Helpers
    private func key(for asset: PHAsset) -> NSString { asset.localIdentifier as NSString }

    func bind(index: Int, to asset: PHAsset) {
        let assetID = asset.localIdentifier
        indexToAssetID[index] = assetID
        assetIDToIndex[assetID] = index
        
        // Update scroll velocity for predictive preloading
        updateScrollVelocity(newIndex: index)
    }
    
    // MARK: - Predictive Preloading
    
    private func updateScrollVelocity(newIndex: Int) {
        let now = Date()
        
        if let lastTime = lastIndexChangeTime,
           let lastIdx = lastIndex {

            let timeDelta = now.timeIntervalSince(lastTime)
            let indexDelta = abs(newIndex - lastIdx)

            // FIX: Guard against near-zero timeDelta causing velocity explosion
            // (was producing 369,076 items/sec, inflating predictive preload window)
            // Two events firing sub-millisecond apart (e.g. from the same swipe gesture)
            // produce near-zero deltas and nonsensical velocities.
            if timeDelta > 0.05 {  // Only update if events are at least 50ms apart
                let instantVelocity = Double(indexDelta) / timeDelta

                // Cap at a realistic maximum (nobody swipes 10 items/sec)
                let clampedVelocity = min(instantVelocity, 10.0)

                // Smooth velocity using exponential moving average
                scrollVelocity = (velocitySmoothing * clampedVelocity) +
                                ((1.0 - velocitySmoothing) * scrollVelocity)
            }
        }
        
        lastIndexChangeTime = now
        lastIndex = newIndex
    }
    
    func getPredictivePreloadDistance() -> Int {
        // Base preload distance is 3
        // Add extra distance based on velocity
        // Fast scrolling (>2 items/sec) = preload +2 extra
        // Medium scrolling (1-2 items/sec) = preload +1 extra
        // Slow scrolling (<1 item/sec) = base distance
        
        let baseDistance = 3
        
        if scrollVelocity > 2.0 {
            return baseDistance + 2  // Fast scroll: 5 items ahead
        } else if scrollVelocity > 1.0 {
            return baseDistance + 1  // Medium scroll: 4 items ahead
        } else {
            return baseDistance  // Slow/normal: 3 items ahead
        }
    }
    
    func getScrollVelocityString() -> String {
        return String(format: "%.2f items/sec", scrollVelocity)
    }

    // MARK: - Asset-based Getters
    func getMediaState(for asset: PHAsset) -> MediaItemState {
        mediaStates[asset.localIdentifier] ?? MediaItemState(loadingState: .loading, loadAttempts: 0)
    }

    /// Reactive publisher for a single asset's media state.
    /// Use this in views instead of a polling Timer.
    func mediaStatePublisher(for assetID: String) -> AnyPublisher<MediaItemState?, Never> {
        $mediaStates
            .map { $0[assetID] }
            .eraseToAnyPublisher()
    }

    func getPlayer(for asset: PHAsset) -> AVQueuePlayer? {
        preloadedPlayers.object(forKey: key(for: asset))?.player
    }

    func getHighQualityImage(for asset: PHAsset) -> UIImage? {
        highQualityImageCache.object(forKey: key(for: asset))
    }

    func getLowQualityImage(for asset: PHAsset) -> UIImage? {
        lowQualityImageCache.object(forKey: key(for: asset))
    }

    // MARK: - Index-based Getters
    func getMediaState(for index: Int) -> MediaItemState {
        guard let assetID = indexToAssetID[index] else {
            return MediaItemState(loadingState: .loading, loadAttempts: 0)
        }
        return mediaStates[assetID] ?? MediaItemState(loadingState: .loading, loadAttempts: 0)
    }

    func getPlayer(for index: Int) -> AVQueuePlayer? {
        guard let assetID = indexToAssetID[index] else { return nil }
        return preloadedPlayers.object(forKey: assetID as NSString)?.player
    }

    func getHighQualityImage(for index: Int) -> UIImage? {
        guard let assetID = indexToAssetID[index] else { return nil }
        return highQualityImageCache.object(forKey: assetID as NSString)
    }

    func getLowQualityImage(for index: Int) -> UIImage? {
        guard let assetID = indexToAssetID[index] else { return nil }
        return lowQualityImageCache.object(forKey: assetID as NSString)
    }

    // MARK: - Playback Control (TikTok-style with tier-based pinning)

    func setActivePlayer(for asset: PHAsset, autoPlay: Bool = true) {
        let assetID = asset.localIdentifier
        
        // Track swipe in telemetry
        telemetry.totalSwipes += 1
        
        // Pause all other players first (like TikTok)
        pauseAllPlayers(except: assetID)
        
        // Set new focus
        currentFocusedAssetID = assetID
        clearTimeout(for: assetID)

        if let cached = preloadedPlayers.object(forKey: key(for: asset)) {
            pinnedPlayersStore[assetID] = cached
            
            if autoPlay && !wasBackgrounded {
                // Use global mute preference instead of hardcoded mute
                cached.player.volume = VideoMutePreference.shared.isMuted ? 0.0 : 1.0
                cached.player.play()
            }
        }
        
        // OPTIMIZATION: Update tier-based pinning for current + neighbors
        updateTierBasedPinning()
    }
    
    /// TIER-BASED PINNING: Keep current + neighbor VIDEOS strongly referenced to prevent eviction
    /// OPTIMIZED for iCloud videos - pins videos only (images are lightweight, don't need pinning)
    /// Tier 0: Current video (always pinned)
    /// Tier 1: ±1 videos (pinned for instant navigation)
    /// Tier 2: ±2 videos (pinned for smooth bidirectional scrolling)
    /// Tier 3+: Everything else (can be evicted by NSCache)
    /// NOTE: Images are NOT pinned - they're small and load quickly from NSCache
    private func updateTierBasedPinning() {
        guard let focusedID = currentFocusedAssetID,
              let focusedIndex = assetIDToIndex[focusedID] else {
            return
        }
        
        // Pin ±1 to balance memory usage with smooth navigation
        let tier1Indices = [
            focusedIndex - 1,  // Tier 1 back
            focusedIndex + 1   // Tier 1 forward
        ]
        var keepAssetIDs: Set<String> = [focusedID] // Tier 0


        // Pin tier 1 assets (VIDEOS only)
        for idx in tier1Indices {
            if let assetID = indexToAssetID[idx] {
                if let cached = preloadedPlayers.object(forKey: assetID as NSString) {
                    // Strong reference prevents eviction
                    pinnedPlayersStore[assetID] = cached
                    keepAssetIDs.insert(assetID)
                    
                } else {
                    // This is normal for images OR videos still downloading
                    // Images: won't be in preloadedPlayers (they're in image caches)
                    // Videos: will auto-pin when download completes
                }
            }
        }
        
        // Unpin everything outside tier 0 + tier 1
        let unpinned = pinnedPlayersStore.keys.filter { !keepAssetIDs.contains($0) }
        for assetID in unpinned {
            pinnedPlayersStore.removeValue(forKey: assetID)
            #if DEBUG
            #endif
        }
        
        let videoPinCount = pinnedPlayersStore.count
        if videoPinCount < 2 {
        }
    }
    
    /// Auto-pin assets when they finish loading if they're in tier 1
    /// NOTE: Only pins VIDEOS - images are lightweight and don't need strong references
    private func autoPinIfInTiers(assetID: String, cachedPlayer: CachedPlayer) {
        guard let focusedID = currentFocusedAssetID,
              let focusedIndex = assetIDToIndex[focusedID],
              let assetIndex = assetIDToIndex[assetID] else {
            return
        }

        let distance = abs(assetIndex - focusedIndex)

        // If within tier 1 range (±1), pin it
        if distance == 1 {
            pinnedPlayersStore[assetID] = cachedPlayer
        }
    }

    func pausePlayer(for asset: PHAsset) {
        preloadedPlayers.object(forKey: key(for: asset))?.player.pause()
    }

    func updateVolume(for asset: PHAsset, muted: Bool) {
        preloadedPlayers.object(forKey: key(for: asset))?.player.volume = muted ? 0 : 1
    }

    func pauseAllPlayers(except assetID: String? = nil) {
        // Pause pinned players
        for (id, cached) in pinnedPlayersStore {
            if let except = assetID, id == except { continue }
            cached.player.volume = 0
            cached.player.pause()
        }
        
        // Pause cached players
        for (id, _) in mediaStates {
            if let except = assetID, id == except { continue }
            if let cached = preloadedPlayers.object(forKey: id as NSString) {
                cached.player.volume = 0
                cached.player.pause()
            }
        }
    }

    // MARK: - Progressive Loading API
    
    enum LoadingStage: Int, Comparable {
        case thumbnail = 0    // 200x200, instant
        case preview = 1      // Screen size, 1-2 sec
        case fullQuality = 2  // Original size, on-demand
        
        static func < (lhs: LoadingStage, rhs: LoadingStage) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    func preloadAssetProgressive(_ asset: PHAsset, at index: Int, priority: LoadingStage = .preview) {
        bind(index: index, to: asset)

        let assetID = asset.localIdentifier

        // Cancel any existing task for this asset before starting a new one
        preloadTasks[assetID]?.cancel()

        switch asset.mediaType {
        case .image:
            preloadTasks[assetID] = Task {
                await preloadImageProgressive(asset, priority: priority)
                preloadTasks.removeValue(forKey: assetID)
            }
        case .video:
            preloadTasks[assetID] = Task {
                await preloadVideoProgressive(asset, priority: priority)
                preloadTasks.removeValue(forKey: assetID)
            }
        default:
            break
        }
    }
    
    /// Preheat thumbnails for upcoming assets using the system-level PHCachingImageManager.
    /// Call this with the next 15–20 assets for fast zero-latency thumbnail display.
    func preheatThumbnails(for assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        cachingImageManager.startCachingImages(
            for: assets,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFit,
            options: options
        )
    }

    /// Stop preheating thumbnails that are no longer upcoming (left the window).
    func stopPreheatingThumbnails(for assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        cachingImageManager.stopCachingImages(
            for: assets,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFit,
            options: options
        )
    }

    /// Upgrade the current item to full quality — called after dwell detection fires.
    func upgradeToFullQuality(for asset: PHAsset) {
        guard asset.mediaType == .image else { return }
        Task {
            await loadFullQuality(asset)
        }
    }

    private func preloadImageProgressive(_ asset: PHAsset, priority: LoadingStage) async {
        // FIX: Bail immediately if this task was cancelled before it even started.
        // Previously cancelled tasks kept running to completion because there were no
        // checkpoints, causing 15x the expected number of concurrent PHImageManager requests.
        guard !Task.isCancelled else { return }

        // FIX: Check memory budget here — this path (1768 calls vs 15 video calls) was
        // never calling checkMemoryBudget(), so the 300MB threshold was never triggered.
        checkMemoryBudget()

        telemetry.imageLoadsStarted += 1
        let startTime = Date()

        // Stage 1: Always load thumbnail first
        await loadThumbnail(asset)
        guard !Task.isCancelled else { return }

        // Stage 2: Load preview if requested
        if priority >= .preview {
            await loadPreview(asset)
            guard !Task.isCancelled else { return }

            // Stage 3: Load full quality if requested
            if priority >= .fullQuality {
                await loadFullQuality(asset)
            }
        }

        telemetry.imageLoadsCompleted += 1
        let loadTime = Date().timeIntervalSince(startTime)
        telemetry.imageLoadTimes.append(loadTime)
        if telemetry.imageLoadTimes.count > 200 { telemetry.imageLoadTimes.removeFirst() }
    }
    
    private func loadThumbnail(_ asset: PHAsset) async {
        guard !Task.isCancelled else { return }
        let key = "\(asset.localIdentifier)_thumb"
        if thumbnailCache.object(forKey: key as NSString) != nil { return }

        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat  // OPTIMIZED: Use fastest delivery mode for thumbnails
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false  // Skip iCloud for speed - thumbnails should be local
            options.isSynchronous = false  // Stay async

            var hasResumed = false

            let reqID = cachingImageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard !hasResumed else { return }
                hasResumed = true
                self?.imageRequestIDs.removeValue(forKey: key)  // request is done

                if let image = image {
                    let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
                    self?.thumbnailCache.setObject(image, forKey: key as NSString, cost: cost)
                    self?.progressiveCacheKeys.insert(key)
                }
                continuation.resume()
            }
            imageRequestIDs[key] = reqID  // store so cancelTasks() can cancel it
        }
    }

    private func loadPreview(_ asset: PHAsset) async {
        guard !Task.isCancelled else { return }
        let key = "\(asset.localIdentifier)_preview"
        if previewCache.object(forKey: key as NSString) != nil {
            return
        }

        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic  // Fast degraded image first, silently upgraded if better arrives quickly
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false  // Stay async
            
            let screenScale = UIScreen.main.scale
            let screenSize = UIScreen.main.bounds.size
            let targetSize = CGSize(
                width: screenSize.width * screenScale,
                height: screenSize.height * screenScale
            )
            
            var hasResumed = false  // Prevent multiple resumes

            let reqID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                if let image = image {
                    // Always update cache — .opportunistic delivers degraded first, then better quality.
                    // Both are stored so the view gets the best available without waiting.
                    let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
                    self?.previewCache.setObject(image, forKey: key as NSString, cost: cost)
                    self?.progressiveCacheKeys.insert(key)

                    if !hasResumed {
                        hasResumed = true
                        self?.imageRequestIDs.removeValue(forKey: key)  // request is done
                        continuation.resume()
                    }
                    // Second callback (full quality) updates cache silently — no resume needed
                } else if !hasResumed {
                    hasResumed = true
                    self?.imageRequestIDs.removeValue(forKey: key)  // request is done (error/cancel)
                    continuation.resume()
                }
            }
            imageRequestIDs[key] = reqID  // store so cancelTasks() can cancel it
        }
    }
    
    private func loadFullQuality(_ asset: PHAsset) async {
        guard !Task.isCancelled else { return }
        let key = "\(asset.localIdentifier)_full"
        if fullQualityCache.object(forKey: key as NSString) != nil { return }

        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false  // Stay async

            var hasResumed = false

            // CRITICAL: Add timeout to prevent infinite waits
            let timeoutWork = DispatchWorkItem {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutWork)

            // FIX: Cap at screen resolution instead of PHImageManagerMaximumSize.
            // Original full-res photos (e.g. 48MP on iPhone 15 Pro) can be 100-190MB each.
            // A 3x Retina screen-size image (~1170×2532) is ~11MB — visually identical on device.
            let screenScale = min(UIScreen.main.scale, 3.0)
            let screenSize = UIScreen.main.bounds.size
            let targetSize = CGSize(
                width: screenSize.width * screenScale,
                height: screenSize.height * screenScale
            )

            let reqID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard !hasResumed else { return }

                timeoutWork.cancel()  // Cancel timeout if we got result
                hasResumed = true
                self?.imageRequestIDs.removeValue(forKey: key)  // request is done

                if let image = image {
                    // Accept first result — iOS often delivers a "degraded" version that's perfect quality
                    let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
                    self?.fullQualityCache.setObject(image, forKey: key as NSString, cost: cost)
                    self?.progressiveCacheKeys.insert(key)
                }
                continuation.resume()
            }
            imageRequestIDs[key] = reqID  // store so cancelTasks() can cancel it
        }
    }
    
    private func preloadVideoProgressive(_ asset: PHAsset, priority: LoadingStage) async {
        // PHASE 1: Load poster frame FIRST (instant visual feedback)
        await loadVideoThumbnail(asset)
        
        // PHASE 2: Load full video player (only if needed)
        if priority >= .preview {
            await preloadVideo(asset)
        }
    }
    
    private func loadVideoThumbnail(_ asset: PHAsset) async {
        let key = "\(asset.localIdentifier)_video_thumb"
        if thumbnailCache.object(forKey: key as NSString) != nil { return }

        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat  // Fast poster frame
            options.isNetworkAccessAllowed = false  // Don't wait for iCloud (poster should be local)
            options.isSynchronous = false
            
            var hasResumed = false
            
            // Request screen-size poster (better quality than 300x300)
            let screenScale = UIScreen.main.scale
            let screenSize = UIScreen.main.bounds.size
            let targetSize = CGSize(
                width: screenSize.width * screenScale * 0.5,  // Half scale for poster is fine
                height: screenSize.height * screenScale * 0.5
            )

            let reqID = cachingImageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard !hasResumed else { return }
                hasResumed = true
                self?.imageRequestIDs.removeValue(forKey: key)  // request is done

                if let image = image {
                    let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
                    self?.thumbnailCache.setObject(image, forKey: key as NSString, cost: cost)
                    self?.progressiveCacheKeys.insert(key)
                }
                continuation.resume()
            }
            imageRequestIDs[key] = reqID  // store so cancelTasks() can cancel it
        }
    }
    
    func getBestAvailableImage(for asset: PHAsset) -> UIImage? {
        let assetID = asset.localIdentifier
        
        // For videos: try video poster first
        if asset.mediaType == .video {
            if let posterImage = thumbnailCache.object(forKey: "\(assetID)_video_thumb" as NSString) {
                return posterImage
            }
        }
        
        // Try full quality first
        if let fullImage = fullQualityCache.object(forKey: "\(assetID)_full" as NSString) {
            return fullImage
        }
        
        // Try preview quality
        if let previewImage = previewCache.object(forKey: "\(assetID)_preview" as NSString) {
            return previewImage
        }
        
        // Try legacy high quality cache
        if let hqImage = highQualityImageCache.object(forKey: assetID as NSString) {
            return hqImage
        }
        
        // Fall back to thumbnail
        if let thumbImage = thumbnailCache.object(forKey: "\(assetID)_thumb" as NSString) {
            return thumbImage
        }
        
        // Final fallback to legacy low quality
        return lowQualityImageCache.object(forKey: assetID as NSString)
    }
    
    /// Get video poster frame (for showing before player loads)
    func getVideoPoster(for asset: PHAsset) -> UIImage? {
        guard asset.mediaType == .video else { return nil }
        let key = "\(asset.localIdentifier)_video_thumb"
        return thumbnailCache.object(forKey: key as NSString)
    }

    func preloadAsset(_ asset: PHAsset) {
        let assetID = asset.localIdentifier

        // If focused and already have a player, don't replace
        if let focused = currentFocusedAssetID, focused == assetID,
           preloadedPlayers.object(forKey: key(for: asset)) != nil,
           asset.mediaType == .video {
            updateMediaState(for: assetID, state: .loaded)
            return
        }

        cancelTasks(for: assetID)
        updateMediaState(for: assetID, state: .loading, incrementAttempts: true)

        if currentFocusedAssetID != assetID {
            setupTimeout(for: asset)
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            if asset.mediaType == .video {
                await self.preloadVideo(asset)
            } else {
                await self.preloadImages(asset)
            }
        }
        preloadTasks[assetID] = task
    }

    func preloadAsset(_ asset: PHAsset, at index: Int) {
        bind(index: index, to: asset)
        preloadAsset(asset)
    }

    // MARK: - Timeout Management
    private func setupTimeout(for asset: PHAsset) {
        let assetID = asset.localIdentifier
        if currentFocusedAssetID == assetID { return }

        let duration = getTimeoutDuration(for: asset)
        let timeoutWork = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateMediaState(for: assetID, state: .timeoutError)
                self?.cancelTasks(for: assetID)
            }
        }
        timeoutTasks[assetID] = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: timeoutWork)
    }
    
    /// OPTIMIZATION: Get timeout duration based on whether asset is in iCloud
    private func getTimeoutDuration(for asset: PHAsset) -> TimeInterval {
        let resources = PHAssetResource.assetResources(for: asset)
        let isLocallyAvailable = resources.contains { 
            let locallyAvailable = $0.value(forKey: "locallyAvailable") as? Bool
            return locallyAvailable == true
        }
        
        // Local videos: 2 seconds is plenty
        // iCloud videos: Need more time to download
        return isLocallyAvailable ? 2.0 : 10.0
    }

    private func clearTimeout(for assetID: String) {
        timeoutTasks[assetID]?.cancel()
        timeoutTasks[assetID] = nil
    }

    private func cancelTasks(for assetID: String) {
        preloadTasks[assetID]?.cancel()
        preloadTasks[assetID] = nil
        highQualityTasks[assetID]?.cancel()
        highQualityTasks[assetID] = nil
        clearTimeout(for: assetID)

        // Cancel any in-flight PHImageManager requests for this asset.
        // Task.cancel() only sets a flag — it doesn't stop a PHImageManager request that's
        // already waiting for a callback. Calling cancelImageRequest() makes PHImageManager
        // fire the callback immediately with nil, which resumes the continuation and lets
        // the guard !Task.isCancelled checks exit the load chain right away.
        // This is what actually reduces concurrent requests from 10× to ~6× per swipe.
        let suffixes = ["_thumb", "_preview", "_full", "_video_thumb"]
        for suffix in suffixes {
            let reqKey = "\(assetID)\(suffix)"
            if let reqID = imageRequestIDs[reqKey] {
                if suffix == "_preview" || suffix == "_full" {
                    PHImageManager.default().cancelImageRequest(reqID)
                } else {
                    cachingImageManager.cancelImageRequest(reqID)
                }
                imageRequestIDs.removeValue(forKey: reqKey)
            }
        }
    }

    private func updateMediaState(for assetID: String, state: MediaLoadingState, incrementAttempts: Bool = false) {
        let currentState = mediaStates[assetID] ?? MediaItemState(loadingState: .loading, loadAttempts: 0)
        let newAttempts = incrementAttempts ? currentState.loadAttempts + 1 : currentState.loadAttempts
        mediaStates[assetID] = MediaItemState(loadingState: state, loadAttempts: newAttempts)
    }

    // MARK: - Video Preloading
    private func preloadVideo(_ asset: PHAsset) async {
        let assetID = asset.localIdentifier
        let loadStartTime = Date()
        
        // CRITICAL: Check if already cached FIRST before any work
        if let existing = preloadedPlayers.object(forKey: key(for: asset)) {
            if let focused = currentFocusedAssetID, focused == assetID {
                pinnedPlayersStore[assetID] = existing
            }
            updateMediaState(for: assetID, state: .loaded)
            telemetry.cacheHits += 1
            return
        }
        
        telemetry.cacheMisses += 1
        
        // CRITICAL: Check if already loading (prevent duplicates)
        if let state = mediaStates[assetID] {
            if state.loadingState == .loading {
                return
            }
        }
        
        // PERFORMANCE: Check memory budget before loading expensive video
        checkMemoryBudget()
        
        // Mark as loading
        updateMediaState(for: assetID, state: .loading)
        telemetry.videoLoadsStarted += 1
        
        // OPTIMIZATION: Detect if asset is in iCloud and needs download
        let resources = PHAssetResource.assetResources(for: asset)
        let isInCloud = resources.contains { 
            let locallyAvailable = $0.value(forKey: "locallyAvailable") as? Bool
            return locallyAvailable == false
        }
        
        if isInCloud {
            telemetry.iCloudDownloadsStarted += 1
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .mediumQualityFormat  // OPTIMIZED: Use medium quality instead of high for better memory
        options.version = .current  // Use current version, not original
        
        // OPTIMIZATION: For iCloud videos, use high priority to download faster
        if isInCloud {
            options.deliveryMode = .fastFormat  // Faster initial playback for iCloud videos
        }
        options.progressHandler = { [weak self] progress, error, stop, info in
            guard let self else { return }
            
            // Show download progress for iCloud videos
            if isInCloud && progress > 0 {
                Task { @MainActor in
                }
            }
            
            if let error = error {
                let nsError = error as NSError
                // Only stop for non-recoverable errors
                let isRecoverable = nsError.code == -12785 || 
                                   nsError.domain == NSURLErrorDomain ||
                                   nsError.code == AVError.Code.mediaServicesWereReset.rawValue
                
                if !isRecoverable {
                    Task { @MainActor in
                        if nsError.domain == NSURLErrorDomain {
                            self.updateMediaState(for: assetID, state: .networkError)
                        } else {
                            self.updateMediaState(for: assetID, state: .error(error))
                        }
                        self.cancelTasks(for: assetID)
                    }
                    stop.pointee = true
                } else if nsError.domain == NSURLErrorDomain {
                    // Network error during iCloud download - this is expected, keep trying
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] playerItem, info in
                Task { @MainActor [weak self] in
                    guard let self else { continuation.resume(); return }

                    self.clearTimeout(for: assetID)
                    self.cancelTasks(for: assetID)

                    if let focused = self.currentFocusedAssetID, focused == assetID,
                       let existing = self.preloadedPlayers.object(forKey: self.key(for: asset)) {
                        self.pinnedPlayersStore[assetID] = existing
                        self.updateMediaState(for: assetID, state: .loaded)
                        
                        let loadTime = Date().timeIntervalSince(loadStartTime)
                        self.telemetry.videoLoadsCompleted += 1
                        self.telemetry.videoLoadTimes.append(loadTime)
                        if self.telemetry.videoLoadTimes.count > 200 { self.telemetry.videoLoadTimes.removeFirst() }

                        if isInCloud {
                            self.telemetry.iCloudDownloadsCompleted += 1
                            self.telemetry.iCloudDownloadTimes.append(loadTime)
                            if self.telemetry.iCloudDownloadTimes.count > 200 { self.telemetry.iCloudDownloadTimes.removeFirst() }
                        }

                        continuation.resume()
                        return
                    }

                    if let playerItem = playerItem {
                        let cachedPlayer = CachedPlayer(playerItem: playerItem)
                        self.preloadedPlayers.setObject(cachedPlayer, forKey: self.key(for: asset))

                        if self.currentFocusedAssetID == assetID {
                            self.pinnedPlayersStore[assetID] = cachedPlayer
                            // Auto-play: setActivePlayer was called before the video finished loading,
                            // so the play() call was a no-op. Trigger it now that the player is ready.
                            if !self.wasBackgrounded {
                                cachedPlayer.player.volume = VideoMutePreference.shared.isMuted ? 0.0 : 1.0
                                cachedPlayer.player.play()
                            }
                        }

                        // CRITICAL: Auto-pin if this asset is in tier 1
                        self.autoPinIfInTiers(assetID: assetID, cachedPlayer: cachedPlayer)

                        self.updateMediaState(for: assetID, state: .loaded)
                        
                        let loadTime = Date().timeIntervalSince(loadStartTime)
                        self.telemetry.videoLoadsCompleted += 1
                        self.telemetry.videoLoadTimes.append(loadTime)
                        if self.telemetry.videoLoadTimes.count > 200 { self.telemetry.videoLoadTimes.removeFirst() }

                        if isInCloud {
                            self.telemetry.iCloudDownloadsCompleted += 1
                            self.telemetry.iCloudDownloadTimes.append(loadTime)
                            if self.telemetry.iCloudDownloadTimes.count > 200 { self.telemetry.iCloudDownloadTimes.removeFirst() }
                            #if DEBUG
                            #endif
                        }
                        
                        // PERFORMANCE: Check memory after loading video
                        self.checkMemoryBudget()
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        self.updateMediaState(for: assetID, state: .error(error))
                        self.telemetry.videoLoadsFailed += 1
                        
                        if isInCloud {
                            self.telemetry.iCloudDownloadsFailed += 1
                        }
                    } else {
                        let fallbackError = NSError(
                            domain: "CacheManager",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to load video - may be downloading from iCloud"]
                        )
                        self.updateMediaState(for: assetID, state: .error(fallbackError))
                        self.telemetry.videoLoadsFailed += 1
                        
                        if isInCloud {
                            self.telemetry.iCloudDownloadsFailed += 1
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Image Preloading
    private func preloadImages(_ asset: PHAsset) async {
        // PERFORMANCE: Check memory before loading images
        checkMemoryBudget()
        
        let ok = await preloadThumbnail(asset)
        if ok { await preloadHighQualityImage(asset) }
    }

    private func preloadThumbnail(_ asset: PHAsset) async -> Bool {
        let assetID = asset.localIdentifier

        if lowQualityImageCache.object(forKey: key(for: asset)) != nil {
            return true
        }

        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                Task { @MainActor [weak self] in
                    guard let self else { continuation.resume(returning: false); return }

                    if let error = info?[PHImageErrorKey] as? Error {
                        self.updateMediaState(for: assetID, state: .error(error))
                        continuation.resume(returning: false)
                    } else if let image = image {
                        self.lowQualityImageCache.setObject(image, forKey: self.key(for: asset))
                        continuation.resume(returning: true)
                    } else {
                        let fallbackError = NSError(
                            domain: "CacheManager",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to load thumbnail"]
                        )
                        self.updateMediaState(for: assetID, state: .error(fallbackError))
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    private func preloadHighQualityImage(_ asset: PHAsset) async {
        let assetID = asset.localIdentifier

        if highQualityImageCache.object(forKey: key(for: asset)) != nil {
            updateMediaState(for: assetID, state: .loaded)
            return
        }

        await withCheckedContinuation { continuation in
            let screenScale = UIScreen.main.scale
            let screenBounds = UIScreen.main.bounds
            // OPTIMIZED: Cap at 2x scale even on 3x devices to save memory
            let effectiveScale = min(screenScale, 2.0)
            let targetSize = CGSize(width: screenBounds.width * effectiveScale,
                                    height: screenBounds.height * effectiveScale)

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact  // Important: ensures we get the exact size we request
            options.isNetworkAccessAllowed = true
            // PERFORMANCE: Deliver result synchronously if possible to avoid multiple callbacks
            options.isSynchronous = false  // Keep async for better performance

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                Task { @MainActor [weak self] in
                    guard let self else { continuation.resume(); return }

                    if let image = image {
                        self.highQualityImageCache.setObject(image, forKey: self.key(for: asset))
                        if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, !degraded {
                            self.updateMediaState(for: assetID, state: .loaded)
                            
                            // PERFORMANCE: Check memory after loading high quality image
                            self.checkMemoryBudget()
                        }
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        self.updateMediaState(for: assetID, state: .error(error))
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Cleanup Management
    
    func unpinAllPlayers(except keepAssetIDs: Set<String>) {
        var keep = keepAssetIDs
        if let focused = currentFocusedAssetID { keep.insert(focused) }
        for key in pinnedPlayersStore.keys where !keep.contains(key) {
            pinnedPlayersStore[key] = nil
        }
    }

    func cleanup(around currentAsset: PHAsset, window: Int = 2) {
        var keepAssetIDs: Set<String> = [currentAsset.localIdentifier]

        if let focused = currentFocusedAssetID {
            keepAssetIDs.insert(focused)
            if let focusedIndex = assetIDToIndex[focused] {
                let neighborRange = (focusedIndex - max(2, window))...(focusedIndex + max(2, window))
                for idx in neighborRange {
                    if let id = indexToAssetID[idx] { keepAssetIDs.insert(id) }
                }
            }
        }

        if let currentIndex = assetIDToIndex[currentAsset.localIdentifier] {
            let range = (currentIndex - window)...(currentIndex + window)
            for index in range {
                if let assetID = indexToAssetID[index] { keepAssetIDs.insert(assetID) }
            }
        }

        unpinAllPlayers(except: keepAssetIDs)

        for assetID in mediaStates.keys where !keepAssetIDs.contains(assetID) {
            if let cachedPlayer = preloadedPlayers.object(forKey: assetID as NSString) {
                cachedPlayer.cleanup()
            }
            preloadedPlayers.removeObject(forKey: assetID as NSString)
            highQualityImageCache.removeObject(forKey: assetID as NSString)
            lowQualityImageCache.removeObject(forKey: assetID as NSString)
            mediaStates[assetID] = nil
            cancelTasks(for: assetID)

            // Trim index maps so they don't grow unboundedly over a long session
            if let idx = assetIDToIndex[assetID] {
                indexToAssetID.removeValue(forKey: idx)
            }
            assetIDToIndex.removeValue(forKey: assetID)

            // Trim progressive cache key entries for this asset
            progressiveCacheKeys.remove("\(assetID)_thumb")
            progressiveCacheKeys.remove("\(assetID)_preview")
            progressiveCacheKeys.remove("\(assetID)_full")
            progressiveCacheKeys.remove("\(assetID)_video_thumb")
        }
    }

    func clearAll() {
        cachingImageManager.stopCachingImagesForAllAssets()

        for (_, cached) in pinnedPlayersStore { cached.cleanup() }
        for key in getAllCachedPlayerKeys() {
            preloadedPlayers.object(forKey: key)?.cleanup()
        }

        preloadedPlayers.removeAllObjects()
        highQualityImageCache.removeAllObjects()
        lowQualityImageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
        previewCache.removeAllObjects()
        fullQualityCache.removeAllObjects()

        mediaStates.removeAll()
        pinnedPlayersStore.removeAll()
        currentFocusedAssetID = nil
        indexToAssetID.removeAll()
        assetIDToIndex.removeAll()
        userPausedStates.removeAll()
        progressiveCacheKeys.removeAll()  // was never cleared — caused unbounded growth
        wasBackgrounded = false

        preloadTasks.values.forEach { $0.cancel() }
        timeoutTasks.values.forEach { $0.cancel() }
        highQualityTasks.values.forEach { $0.cancel() }

        preloadTasks.removeAll()
        timeoutTasks.removeAll()
        highQualityTasks.removeAll()

        // Cancel all in-flight PHImageManager requests
        for (reqKey, reqID) in imageRequestIDs {
            if reqKey.hasSuffix("_preview") || reqKey.hasSuffix("_full") {
                PHImageManager.default().cancelImageRequest(reqID)
            } else {
                cachingImageManager.cancelImageRequest(reqID)
            }
        }
        imageRequestIDs.removeAll()
    }

    // MARK: - Debug Utilities
    
    private func logEviction(assetID: String, cacheType: String, reason: String) {
        let memoryMB = Int(getMemoryUsed() / 1_000_000)
        let event = EvictionEvent(
            assetID: assetID,
            cacheType: cacheType,
            timestamp: Date(),
            memoryAtEviction: memoryMB,
            reason: reason
        )
        
        evictionLog.append(event)
        
        // Trim log if too large
        if evictionLog.count > maxEvictionLogSize {
            evictionLog.removeFirst(evictionLog.count - maxEvictionLogSize)
        }
        
    }
    
    func getEvictionStats() -> String {
        guard !evictionLog.isEmpty else {
            return "No evictions recorded"
        }
        
        let playerEvictions = evictionLog.filter { $0.cacheType.contains("player") }.count
        let imageEvictions = evictionLog.filter { $0.cacheType.contains("image") || $0.cacheType.contains("quality") }.count
        let memoryEvictions = evictionLog.filter { $0.reason.contains("memory") }.count
        let cleanupEvictions = evictionLog.filter { $0.reason.contains("cleanup") }.count
        
        let avgMemory = evictionLog.map { $0.memoryAtEviction }.reduce(0, +) / evictionLog.count
        
        // Get recent evictions (last 10)
        let recentCount = min(10, evictionLog.count)
        let recentEvictions = evictionLog.suffix(recentCount)
        let recentLog = recentEvictions.map { event in
            let timestamp = DateFormatter.localizedString(from: event.timestamp, dateStyle: .none, timeStyle: .medium)
            return "  • \(timestamp) - \(event.cacheType) - \(event.assetID.prefix(8)) - \(event.reason)"
        }.joined(separator: "\n")
        
        return """
        📊 EVICTION STATISTICS
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Total Evictions: \(evictionLog.count)
        Player Evictions: \(playerEvictions)
        Image Evictions: \(imageEvictions)
        Memory Pressure Evictions: \(memoryEvictions)
        Cleanup Evictions: \(cleanupEvictions)
        Average Memory at Eviction: \(avgMemory)MB
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Recent Evictions (last \(recentCount)):
        \(recentLog)
        """
    }
    
    func getTelemetryReport() -> String {
        let sessionMinutes = Int(telemetry.sessionDuration / 60)
        
        return """
        
        📊 CACHE TELEMETRY REPORT
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        SESSION INFO
        Duration: \(sessionMinutes) minutes
        Total Swipes: \(telemetry.totalSwipes)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        VIDEO METRICS
        Loads Started: \(telemetry.videoLoadsStarted)
        Loads Completed: \(telemetry.videoLoadsCompleted)
        Loads Failed: \(telemetry.videoLoadsFailed)
        Success Rate: \(String(format: "%.1f%%", telemetry.videoLoadSuccessRate * 100))
        Avg Load Time: \(String(format: "%.2fs", telemetry.avgVideoLoadTime))
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        IMAGE METRICS
        Loads Started: \(telemetry.imageLoadsStarted)
        Loads Completed: \(telemetry.imageLoadsCompleted)
        Loads Failed: \(telemetry.imageLoadsFailed)
        Success Rate: \(String(format: "%.1f%%", telemetry.imageLoadSuccessRate * 100))
        Avg Load Time: \(String(format: "%.2fs", telemetry.avgImageLoadTime))
        Avg Poster Load: \(String(format: "%.2fs", telemetry.avgPosterLoadTime))
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        CACHE PERFORMANCE
        Cache Hits: \(telemetry.cacheHits)
        Cache Misses: \(telemetry.cacheMisses)
        Hit Rate: \(String(format: "%.1f%%", telemetry.cacheHitRate * 100))
        Evictions: \(telemetry.evictionCount)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        MEMORY METRICS
        Peak Memory: \(telemetry.peakMemoryMB)MB
        Average Memory: \(telemetry.averageMemoryMB)MB
        Current Memory: \(currentMemoryUsageMB)MB
        Budget: \(maxTotalMemoryMB)MB
        Memory Warnings: \(telemetry.memoryWarnings)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        iCLOUD METRICS
        Downloads Started: \(telemetry.iCloudDownloadsStarted)
        Downloads Completed: \(telemetry.iCloudDownloadsCompleted)
        Downloads Failed: \(telemetry.iCloudDownloadsFailed)
        Avg Download Time: \(String(format: "%.2fs", telemetry.iCloudDownloadTimes.isEmpty ? 0 : telemetry.iCloudDownloadTimes.reduce(0, +) / Double(telemetry.iCloudDownloadTimes.count)))
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        SCROLL METRICS
        Current Velocity: \(getScrollVelocityString())
        Predictive Distance: \(getPredictivePreloadDistance()) items
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """
    }
    
    func getCacheStatusSummary() -> String {
        return """
        Cache Manager Status:
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Players Cache (limit: \(preloadedPlayers.countLimit))
        HQ Images Cache (limit: \(highQualityImageCache.countLimit))
        LQ Images Cache (limit: \(lowQualityImageCache.countLimit))
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Tracked Media States: \(mediaStates.count)
        Pinned Players (strong): \(pinnedPlayersStore.count)
        Focused Asset: \(currentFocusedAssetID ?? "nil")
        Was Backgrounded: \(wasBackgrounded)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Active Tasks:
        - Preload: \(preloadTasks.count)
        - High Quality: \(highQualityTasks.count)
        - Timeouts: \(timeoutTasks.count)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """
    }

    private func getAllCachedPlayerKeys() -> [NSString] {
        // NSCache doesn't provide key enumeration
        return []
    }
}

