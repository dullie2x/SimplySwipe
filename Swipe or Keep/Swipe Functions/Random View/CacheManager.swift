//
//  CacheManager.swift
//  Media App
//
//  Created on [Date]
//

import SwiftUI
import Photos
import AVKit

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
        let queue = AVQueuePlayer(playerItem: playerItem)
        queue.automaticallyWaitsToMinimizeStalling = true
        queue.volume = 0
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
    
    // MARK: - Progressive Loading Caches
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let previewCache = NSCache<NSString, UIImage>()
    private let fullQualityCache = NSCache<NSString, UIImage>()

    // MARK: - Memory Management
    private let maxTotalMemoryMB: Int = 800  // 800MB total limit
    private var currentMemoryUsageMB: Int = 0

    // MARK: - State Management
    @Published private var mediaStates: [String: MediaItemState] = [:]
    private(set) var currentFocusedAssetID: String?
    private var pinnedPlayersStore: [String: CachedPlayer] = [:]
    
    // Background state tracking (simplified)
    private var wasBackgrounded: Bool = false
    private var userPausedStates: [String: Bool] = [:]

    // Optional index↔︎assetID mapping
    private var indexToAssetID: [Int: String] = [:]
    private var assetIDToIndex: [String: Int] = [:]

    // MARK: - Task Management
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    private var timeoutTasks: [String: DispatchWorkItem] = [:]
    private var highQualityTasks: [String: Task<Void, Never>] = [:]

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
    }
    
    private func setupCacheLimits() {
        // Progressive cache limits (smaller, more efficient)
        thumbnailCache.countLimit = 50      // Keep many small thumbnails
        previewCache.countLimit = 15        // Moderate preview images
        fullQualityCache.countLimit = 5     // Few full quality images
        
        // Traditional cache limits (reduced)
        preloadedPlayers.countLimit = 6     // Reduced from 8
        highQualityImageCache.countLimit = 8  // Reduced from 24
        lowQualityImageCache.countLimit = 20  // Reduced from 32
    }
    
    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning - aggressive cleanup")
        aggressiveCleanup()
    }
    
    private func aggressiveCleanup() {
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
        // Cleanup players
        for (assetID, cached) in pinnedPlayersStore where !keepAssetIDs.contains(assetID) {
            cached.cleanup()
            pinnedPlayersStore[assetID] = nil
        }
        
        // Cleanup states
        for assetID in mediaStates.keys where !keepAssetIDs.contains(assetID) {
            if let cached = preloadedPlayers.object(forKey: assetID as NSString) {
                cached.cleanup()
            }
            preloadedPlayers.removeObject(forKey: assetID as NSString)
            highQualityImageCache.removeObject(forKey: assetID as NSString)
            lowQualityImageCache.removeObject(forKey: assetID as NSString)
            mediaStates[assetID] = nil
            cancelTasks(for: assetID)
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
    
    private func getAllCachedKeys() -> [String] {
        // Helper to get all cached keys - would need proper implementation
        return []
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
        
        // Re-establish audio session first
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to reactivate audio session: \(error)")
        }
        
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
    }

    // MARK: - Asset-based Getters
    func getMediaState(for asset: PHAsset) -> MediaItemState {
        mediaStates[asset.localIdentifier] ?? MediaItemState(loadingState: .loading, loadAttempts: 0)
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

    // MARK: - Playback Control (TikTok-style but simplified)

    func setActivePlayer(for asset: PHAsset, autoPlay: Bool = true) {
        let assetID = asset.localIdentifier
        
        // Pause all other players first (like TikTok)
        pauseAllPlayers(except: assetID)
        
        // Set new focus
        currentFocusedAssetID = assetID
        clearTimeout(for: assetID)

        if let cached = preloadedPlayers.object(forKey: key(for: asset)) {
            pinnedPlayersStore[assetID] = cached
            
            if autoPlay && !wasBackgrounded {
                // Start muted by default (will be controlled by view model)
                cached.player.volume = 0.0
                cached.player.play()
            }
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
        
        switch asset.mediaType {
        case .image:
            Task {
                await preloadImageProgressive(asset, priority: priority)
            }
        case .video:
            Task {
                await preloadVideoProgressive(asset, priority: priority)
            }
        default:
            break
        }
    }
    
    private func preloadImageProgressive(_ asset: PHAsset, priority: LoadingStage) async {
        // Stage 1: Always load thumbnail first
        await loadThumbnail(asset)
        
        // Stage 2: Load preview if requested
        if priority >= .preview {
            await loadPreview(asset)
            
            // Stage 3: Load full quality if requested
            if priority >= .fullQuality {
                await loadFullQuality(asset)
            }
        }
    }
    
    private func loadThumbnail(_ asset: PHAsset) async {
        let key = "\(asset.localIdentifier)_thumb"
        if thumbnailCache.object(forKey: key as NSString) != nil { return }
        
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false  // Skip iCloud for speed
            
            var hasResumed = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard !hasResumed else { return }
                hasResumed = true
                
                if let image = image {
                    self?.thumbnailCache.setObject(image, forKey: key as NSString)
                }
                continuation.resume()
            }
        }
    }
    
    private func loadPreview(_ asset: PHAsset) async {
        let key = "\(asset.localIdentifier)_preview"
        if previewCache.object(forKey: key as NSString) != nil { return }
        
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            
            let screenScale = UIScreen.main.scale
            let screenSize = UIScreen.main.bounds.size
            let targetSize = CGSize(
                width: screenSize.width * screenScale,
                height: screenSize.height * screenScale
            )
            
            var hasResumed = false  // Prevent multiple resumes
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard !hasResumed else { return }  // Prevent multiple calls
                
                if let image = image {
                    // Check if this is the final (non-degraded) result
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    
                    if !isDegraded {
                        // Final high-quality result
                        self?.previewCache.setObject(image, forKey: key as NSString)
                        hasResumed = true
                        continuation.resume()
                    } else {
                        // Degraded result - store it but don't resume yet
                        self?.previewCache.setObject(image, forKey: key as NSString)
                        // Wait for the final result
                    }
                } else {
                    // No image returned, resume anyway
                    hasResumed = true
                    continuation.resume()
                }
            }
        }
    }
    
    private func loadFullQuality(_ asset: PHAsset) async {
        let key = "\(asset.localIdentifier)_full"
        if fullQualityCache.object(forKey: key as NSString) != nil { return }
        
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true
            
            var hasResumed = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard !hasResumed else { return }
                
                if let image = image {
                    let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                    
                    if !isDegraded {
                        // Final high-quality result
                        self?.fullQualityCache.setObject(image, forKey: key as NSString)
                        hasResumed = true
                        continuation.resume()
                    } else {
                        // Degraded result - store it but wait for final
                        self?.fullQualityCache.setObject(image, forKey: key as NSString)
                    }
                } else {
                    // No image, resume anyway
                    hasResumed = true
                    continuation.resume()
                }
            }
        }
    }
    
    private func preloadVideoProgressive(_ asset: PHAsset, priority: LoadingStage) async {
        // For videos: load thumbnail poster + full video player
        await loadVideoThumbnail(asset)
        
        if priority >= .preview {
            await preloadVideo(asset)
        }
    }
    
    private func loadVideoThumbnail(_ asset: PHAsset) async {
        let key = "\(asset.localIdentifier)_video_thumb"
        if thumbnailCache.object(forKey: key as NSString) != nil { return }
        
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            
            var hasResumed = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard !hasResumed else { return }
                hasResumed = true
                
                if let image = image {
                    self?.thumbnailCache.setObject(image, forKey: key as NSString)
                }
                continuation.resume()
            }
        }
    }
    
    func getBestAvailableImage(for asset: PHAsset) -> UIImage? {
        let assetID = asset.localIdentifier
        
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
            setupTimeout(for: assetID)
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
    private func setupTimeout(for assetID: String) {
        if currentFocusedAssetID == assetID { return }

        let timeoutWork = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateMediaState(for: assetID, state: .timeoutError)
                self?.cancelTasks(for: assetID)
            }
        }
        timeoutTasks[assetID] = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDuration, execute: timeoutWork)
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
    }

    private func updateMediaState(for assetID: String, state: MediaLoadingState, incrementAttempts: Bool = false) {
        let currentState = mediaStates[assetID] ?? MediaItemState(loadingState: .loading, loadAttempts: 0)
        let newAttempts = incrementAttempts ? currentState.loadAttempts + 1 : currentState.loadAttempts
        mediaStates[assetID] = MediaItemState(loadingState: state, loadAttempts: newAttempts)
    }

    // MARK: - Video Preloading
    private func preloadVideo(_ asset: PHAsset) async {
        let assetID = asset.localIdentifier

        if let focused = currentFocusedAssetID, focused == assetID,
           let existing = preloadedPlayers.object(forKey: key(for: asset)) {
            pinnedPlayersStore[assetID] = existing
            updateMediaState(for: assetID, state: .loaded)
            return
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.progressHandler = { [weak self] _, error, stop, _ in
            guard let self else { return }
            if let error = error {
                Task { @MainActor in
                    if (error as NSError).domain == NSURLErrorDomain {
                        self.updateMediaState(for: assetID, state: .networkError)
                    } else {
                        self.updateMediaState(for: assetID, state: .error(error))
                    }
                    self.cancelTasks(for: assetID)
                }
                stop.pointee = true
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
                        continuation.resume()
                        return
                    }

                    if let playerItem = playerItem {
                        let cachedPlayer = CachedPlayer(playerItem: playerItem)
                        self.preloadedPlayers.setObject(cachedPlayer, forKey: self.key(for: asset))

                        if self.currentFocusedAssetID == assetID {
                            self.pinnedPlayersStore[assetID] = cachedPlayer
                        }

                        self.updateMediaState(for: assetID, state: .loaded)
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        self.updateMediaState(for: assetID, state: .error(error))
                    } else {
                        let fallbackError = NSError(
                            domain: "CacheManager",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to load video"]
                        )
                        self.updateMediaState(for: assetID, state: .error(fallbackError))
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Image Preloading
    private func preloadImages(_ asset: PHAsset) async {
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
            let targetSize = CGSize(width: screenBounds.width * screenScale,
                                    height: screenBounds.height * screenScale)

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true

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
        }
    }

    func clearAll() {
        for (_, cached) in pinnedPlayersStore { cached.cleanup() }
        for key in getAllCachedPlayerKeys() {
            preloadedPlayers.object(forKey: key)?.cleanup()
        }

        preloadedPlayers.removeAllObjects()
        highQualityImageCache.removeAllObjects()
        lowQualityImageCache.removeAllObjects()

        mediaStates.removeAll()
        pinnedPlayersStore.removeAll()
        currentFocusedAssetID = nil
        indexToAssetID.removeAll()
        assetIDToIndex.removeAll()
        userPausedStates.removeAll()
        wasBackgrounded = false

        preloadTasks.values.forEach { $0.cancel() }
        timeoutTasks.values.forEach { $0.cancel() }
        highQualityTasks.values.forEach { $0.cancel() }

        preloadTasks.removeAll()
        timeoutTasks.removeAll()
        highQualityTasks.removeAll()
    }

    // MARK: - Debug Utilities
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
