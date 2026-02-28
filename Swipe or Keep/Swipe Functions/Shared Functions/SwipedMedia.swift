//OG

import Foundation
import Photos

@MainActor
class SwipedMediaManager: NSObject, ObservableObject {
    static let shared = SwipedMediaManager()
    
    private let swipedKey = "swipedMedia"
    private let trashKey = "trashedItems"
    
    private var swipedMedia: Set<String> = []
    private var trashedItems: Set<String> = []
    
    @Published var trashedMediaAssets: [PHAsset] = []
    @Published var swipeCount: Int = 0
    
    // Paging information
    private let pageSize = 500  // Process assets in pages of 500
    
    // Background queues with different priorities
    private let fetchQueue = DispatchQueue(label: "com.app.swipedMediaManager.fetch", qos: .utility)
    private let progressCalculationQueue = DispatchQueue(label: "com.app.swipedMediaManager.progress", qos: .background)
    
    // Progress calculation caches for different asset types
    private var categoryProgressCache: [MediaCategory: (timestamp: Date, progress: Double)] = [:]
    private var yearProgressCache: [String: (timestamp: Date, progress: Double)] = [:]
    private var albumProgressCache: [String: (timestamp: Date, progress: Double)] = [:]
    
    // Cache freshness threshold - 5 minutes
    private let cacheFreshnessDuration: TimeInterval = 300
    
    // Asset lookup for faster checking - maps asset identifiers to boolean indicating if it's been swiped
    private var assetLookupCache: [String: Bool] = [:]
    
    // Store identifiers of assets that have been processed in calculateProgress methods
    // This prevents redundant processing in subsequent calls
    private var processedAssetIdentifiers: Set<String> = []
    
    // Add a set to track pending updates
    private var pendingProgressUpdates = Set<String>()
    private var progressUpdateTimer: Timer?

    // Debounce timer for UserDefaults saves to avoid per-swipe I/O
    private var saveDebounceTimer: Timer?
    
    // Media category enum
    enum MediaCategory {
        case recents
        case screenshots
        case favorites
    }
    
    private override init() {
        super.init()
        loadSwipedMedia()
        loadTrashedItems()
        updateSwipeCount()
        
        // Pre-fill the asset lookup cache
        updateAssetLookupCache()
        
        // Register for photo library change notifications
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        progressUpdateTimer?.invalidate()
    }
    
    // Update the asset lookup cache for faster checking
    private func updateAssetLookupCache() {
        // Create a lookup dictionary for swiped media for faster access
        for identifier in swipedMedia {
            assetLookupCache[identifier] = true
        }
    }
    
    func addSwipedMedia(_ asset: PHAsset, toTrash: Bool = false) {
        let identifier = asset.localIdentifier
        if toTrash {
            trashedItems.insert(identifier)
            saveTrashedItems()
        }
        swipedMedia.insert(identifier)
        
        // Update the lookup cache
        assetLookupCache[identifier] = true
        
        saveSwipedMedia()
        
        // Schedule an update for trashed media assets
        scheduleTrashedMediaUpdate()
        
        updateSwipeCount()
        
        // Invalidate cached progress values for affected categories
        invalidateProgressCache(for: asset)
    }
    
    // Use a timer to batch update trashed media to prevent too many UI updates
    private func scheduleTrashedMediaUpdate() {
        if progressUpdateTimer == nil {
            progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                // Ensure we're on the main actor when calling actor-isolated methods
                Task { @MainActor [weak self] in
                    self?.updateTrashedMediaAssets()
                    self?.progressUpdateTimer = nil
                }
            }
        }
    }
    
    // Invalidate cached progress values related to this asset
    private func invalidateProgressCache(for asset: PHAsset) {
        // Clear the category cache
        categoryProgressCache.removeAll()
        
        // Clear year cache for this asset's year
        if let creationDate = asset.creationDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM ''yy"
            let year = dateFormatter.string(from: creationDate)
            yearProgressCache.removeValue(forKey: year)
        }
        
        // Clear album caches - we'll just clear all since it's hard to know which albums contain this asset
        albumProgressCache.removeAll()
        
        // Notify ProgressManager to invalidate its caches as well
        Task {
            await ProgressManager.shared.invalidateCache()
        }
    }
    
    func recoverItems(with identifiers: Set<String>) {
        trashedItems.subtract(identifiers)
        // Note: swiped status is intentionally preserved when recovering from trash.
        saveTrashedItems()
        updateTrashedMediaAssets()
    }
    
    func deleteItems(with identifiers: Set<String>) {
        trashedItems.subtract(identifiers)
        // Note: swiped status is intentionally preserved after permanent deletion.
        saveTrashedItems()
        updateTrashedMediaAssets()
    }
    
    func isMediaSwiped(_ asset: PHAsset) -> Bool {
        // Use the lookup cache for faster checking
        if let isSwiped = assetLookupCache[asset.localIdentifier] {
            return isSwiped
        }
        // Fall back to the set if not in cache
        return swipedMedia.contains(asset.localIdentifier)
    }
    
    // Get all swiped media identifiers (for filtering)
    func getSwipedMediaIdentifiers() -> Set<String> {
        return swipedMedia
    }
    
    // Reset all swiped media data
    func resetAllSwipedMedia() {
        swipedMedia.removeAll()
        trashedItems.removeAll()
        
        // Clear the lookup cache
        assetLookupCache.removeAll()
        
        // Clear all progress caches
        categoryProgressCache.removeAll()
        yearProgressCache.removeAll()
        albumProgressCache.removeAll()
        
        saveSwipedMedia()
        saveTrashedItems()
        updateTrashedMediaAssets()
        updateSwipeCount()
        
        // Notify ProgressManager to invalidate its caches
        Task {
            await ProgressManager.shared.invalidateCache()
        }
    }
    
    // MARK: - Reset Functions for Albums/Years/Categories
    
    // Reset specific album's swiped media
    func resetAlbum(_ collection: PHAssetCollection) {
        guard let albumTitle = collection.localizedTitle else { return }
        
        // Get all assets in this album
        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        
        var albumAssetIds: Set<String> = []
        PHAssetBatchProcessor.processBatched(fetchResult: assets, batchSize: 500) { asset in
            albumAssetIds.insert(asset.localIdentifier)
        }
        
        // Remove these assets from swiped media
        swipedMedia.subtract(albumAssetIds)
        trashedItems.subtract(albumAssetIds)
        
        // Update caches
        for assetId in albumAssetIds {
            assetLookupCache.removeValue(forKey: assetId)
        }
        
        // Clear progress cache for this album
        albumProgressCache.removeValue(forKey: albumTitle)
        
        // Save changes
        saveSwipedMedia()
        saveTrashedItems()
        updateSwipeCount()
        updateTrashedMediaAssets()
        
        // Notify ProgressManager
        Task {
            await ProgressManager.shared.invalidateCache(forAlbum: albumTitle)
        }
        
    }
    
    // Reset specific year's swiped media
    func resetYear(_ year: String) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        
        var yearAssetIds: Set<String> = []
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM ''yy"
        
        let isFullYear = year.count == 4 && Int(year) != nil
        
        PHAssetBatchProcessor.processBatched(fetchResult: allAssets, batchSize: 500) { asset in
            guard let creationDate = asset.creationDate else { return }
            
            let matches: Bool
            if isFullYear {
                let assetYear = calendar.component(.year, from: creationDate)
                matches = String(assetYear) == year
            } else {
                let formatted = dateFormatter.string(from: creationDate)
                matches = formatted == year
            }
            
            if matches {
                yearAssetIds.insert(asset.localIdentifier)
            }
        }
        
        // Remove these assets from swiped media
        swipedMedia.subtract(yearAssetIds)
        trashedItems.subtract(yearAssetIds)
        
        // Update caches
        for assetId in yearAssetIds {
            assetLookupCache.removeValue(forKey: assetId)
        }
        
        // Clear progress cache for this year
        yearProgressCache.removeValue(forKey: year)
        
        // Save changes
        saveSwipedMedia()
        saveTrashedItems()
        updateSwipeCount()
        updateTrashedMediaAssets()
        
        // Notify ProgressManager
        Task {
            await ProgressManager.shared.invalidateCache(forYear: year)
        }
        
    }
    
    // Reset specific category's swiped media
    func resetCategory(_ category: MediaCategory) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        var assets: PHFetchResult<PHAsset>
        
        switch category {
        case .recents:
            let calendar = Calendar.current
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
            fetchOptions.predicate = NSPredicate(format: "creationDate > %@", thirtyDaysAgo as NSDate)
            assets = PHAsset.fetchAssets(with: fetchOptions)
        case .screenshots:
            fetchOptions.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        case .favorites:
            fetchOptions.predicate = NSPredicate(format: "favorite == YES")
            assets = PHAsset.fetchAssets(with: fetchOptions)
        }
        
        var categoryAssetIds: Set<String> = []
        PHAssetBatchProcessor.processBatched(fetchResult: assets, batchSize: 500) { asset in
            categoryAssetIds.insert(asset.localIdentifier)
        }
        
        // Remove these assets from swiped media
        swipedMedia.subtract(categoryAssetIds)
        trashedItems.subtract(categoryAssetIds)
        
        // Update caches
        for assetId in categoryAssetIds {
            assetLookupCache.removeValue(forKey: assetId)
        }
        
        // Clear progress cache for this category
        categoryProgressCache.removeValue(forKey: category)
        
        // Save changes
        saveSwipedMedia()
        saveTrashedItems()
        updateSwipeCount()
        updateTrashedMediaAssets()
        
        // Notify ProgressManager
        Task {
            let categoryIndex = category == .recents ? 0 : (category == .screenshots ? 1 : 2)
            await ProgressManager.shared.invalidateCache(forCategory: categoryIndex)
        }
        
    }
    
    // Update the swipe count
    private func updateSwipeCount() {
        swipeCount = swipedMedia.count
        
        // Also update UserDefaults swipeCount to keep it in sync
        UserDefaults.standard.set(swipeCount, forKey: "swipeCount")
    }
    
    // Calculate progress for a collection (album)
    func calculateProgress(for collection: PHAssetCollection) -> Double {
        // Check if we have a fresh cached value
        if let title = collection.localizedTitle,
           let cachedData = albumProgressCache[title],
           Date().timeIntervalSince(cachedData.timestamp) < cacheFreshnessDuration {
            return cachedData.progress
        }
        
        // Skip calculation if no swiped media
        if swipedMedia.isEmpty {
            return 0.0
        }
        
        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        
        if assets.count == 0 {
            return 0.0
        }
        
        var swipedCount = 0
        let totalCount = assets.count
        
        // Skip if no assets to process
        if totalCount == 0 {
            return 0.0
        }
        
        // Process in batches for better performance
        let batchSize = max(1, min(pageSize, totalCount)) // Ensure at least 1 to avoid zero stride
        
        PHAssetBatchProcessor.processBatched(fetchResult: assets, batchSize: batchSize) { asset in
            if isMediaSwiped(asset) {
                swipedCount += 1
            }
        }
        
        let progress = Double(swipedCount) / Double(totalCount)
        
        // Update the cache
        if let title = collection.localizedTitle {
            albumProgressCache[title] = (Date(), progress)
        }
        
        return progress
    }
    
    // Calculate progress for a year - optimized version
    func calculateProgress(forYear year: String) -> Double {
        // Check if we have a fresh cached value
        if let cachedData = yearProgressCache[year],
           Date().timeIntervalSince(cachedData.timestamp) < cacheFreshnessDuration {
            return cachedData.progress
        }
        
        // Skip calculation if there are no swiped media (improves performance)
        if swipedMedia.isEmpty {
            return 0.0
        }
        
        // Use a local instance of the date formatter to avoid threading issues
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM ''yy"
        
        // Get a date range for this year to optimize the fetch
        var yearStartDate: Date?
        var yearEndDate: Date?
        
        // Try to parse the year format to get a date range
        if Calendar.current.dateComponents([.year], from: Date()).year != nil {
            // For formats like "Jan '25", extract the year and month
            let components = year.components(separatedBy: " ")
            if components.count == 2 {
                let shortMonth = components[0]
                let yearStr = components[1].replacingOccurrences(of: "'", with: "")
                
                let monthFormatter = DateFormatter()
                monthFormatter.dateFormat = "MMM"
                
                if let monthDate = monthFormatter.date(from: shortMonth),
                   let shortYear = Int(yearStr) {
                    
                    let fullYear = shortYear < 100 ? 2000 + shortYear : shortYear
                    
                    let month = Calendar.current.component(.month, from: monthDate)
                    
                    var startComponents = DateComponents()
                    startComponents.year = fullYear
                    startComponents.month = month
                    startComponents.day = 1
                    startComponents.hour = 0
                    startComponents.minute = 0
                    startComponents.second = 0
                    
                    var endComponents = DateComponents()
                    endComponents.year = fullYear
                    endComponents.month = month + 1
                    endComponents.day = 0  // Last day of the month
                    endComponents.hour = 23
                    endComponents.minute = 59
                    endComponents.second = 59
                    
                    yearStartDate = Calendar.current.date(from: startComponents)
                    yearEndDate = Calendar.current.date(from: endComponents) ?? Calendar.current.date(byAdding: .month, value: 1, to: yearStartDate!)
                }
            }
        }
        
        // Optimize the fetch with the date range if available
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        if let start = yearStartDate, let end = yearEndDate {
            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", start as NSDate, end as NSDate)
        }
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        var yearAssets = 0
        var swipedCount = 0
        
        // Process in smaller batches for better memory management
        let totalAssets = assets.count
        
        // Skip if no assets to process
        if totalAssets == 0 {
            return 0.0
        }
        
        let batchSize = max(1, min(pageSize, totalAssets)) // Ensure at least 1 to avoid zero stride
        
        PHAssetBatchProcessor.processBatched(fetchResult: assets, batchSize: batchSize) { asset in
            if let creationDate = asset.creationDate {
                let formattedDate = dateFormatter.string(from: creationDate)
                if formattedDate == year {
                    yearAssets += 1
                    if isMediaSwiped(asset) {
                        swipedCount += 1
                    }
                }
            }
        }
        
        if yearAssets == 0 {
            return 0.0
        }
        
        let progress = Double(swipedCount) / Double(yearAssets)
        
        // Update the cache
        yearProgressCache[year] = (Date(), progress)
        
        return progress
    }
    
    
    // Calculate progress for standard categories
    func calculateProgress(forCategory category: MediaCategory) -> Double {
        // Check if we have a fresh cached value
        if let cachedData = categoryProgressCache[category],
           Date().timeIntervalSince(cachedData.timestamp) < cacheFreshnessDuration {
            return cachedData.progress
        }
        
        // Skip calculation if there are no swiped media
        if swipedMedia.isEmpty {
            return 0.0
        }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        var assets: PHFetchResult<PHAsset>
        
        switch category {
        case .recents:
            // For recents, get recent media (last 30 days)
            let calendar = Calendar.current
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
            
            fetchOptions.predicate = NSPredicate(format: "creationDate > %@", thirtyDaysAgo as NSDate)
            assets = PHAsset.fetchAssets(with: fetchOptions)
            
        case .screenshots:
            // For screenshots, get media tagged as screenshots
            fetchOptions.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            
        case .favorites:
            // For favorites, get media marked as favorites
            fetchOptions.predicate = NSPredicate(format: "favorite == YES")
            assets = PHAsset.fetchAssets(with: fetchOptions)
        }
        
        if assets.count == 0 {
            return 0.0
        }
        
        var swipedCount = 0
        let totalCount = assets.count
        
        // Skip if no assets to process
        if totalCount == 0 {
            return 0.0
        }
        
        // Process in batches for better performance
        let batchSize = max(1, min(pageSize, totalCount)) // Ensure at least 1 to avoid zero stride
        
        PHAssetBatchProcessor.processBatched(fetchResult: assets, batchSize: batchSize) { asset in
            if isMediaSwiped(asset) {
                swipedCount += 1
            }
        }
        
        let progress = Double(swipedCount) / Double(totalCount)
        
        // Update the cache
        categoryProgressCache[category] = (Date(), progress)
        
        return progress
    }
    
    private func saveSwipedMedia() {
        // Debounce: batch rapid swipes into a single write, max 1 second delay.
        // Always flush immediately when the app backgrounds (see flushPendingSave).
        saveDebounceTimer?.invalidate()
        
        // Capture the data we need before entering the Sendable closure
        let mediaToSave = Array(swipedMedia)
        let key = swipedKey
        
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            UserDefaults.standard.set(mediaToSave, forKey: key)
            
            // Clear the timer on the main actor
            Task { @MainActor [weak self] in
                self?.saveDebounceTimer = nil
            }
        }
    }

    /// Call this when the app backgrounds to flush any pending save immediately.
    func flushPendingSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil
        UserDefaults.standard.set(Array(swipedMedia), forKey: swipedKey)
    }
    
    private func loadSwipedMedia() {
        swipedMedia = Set(UserDefaults.standard.stringArray(forKey: swipedKey) ?? [])
        // Update the lookup cache after loading
        updateAssetLookupCache()
    }
    
    private func saveTrashedItems() {
        UserDefaults.standard.set(Array(trashedItems), forKey: trashKey)
    }
    
    private func loadTrashedItems() {
        trashedItems = Set(UserDefaults.standard.stringArray(forKey: trashKey) ?? [])
        updateTrashedMediaAssets()
    }
    
    private func updateTrashedMediaAssets() {
        // Skip updating if there are no trashed items
        guard !trashedItems.isEmpty else {
            self.trashedMediaAssets = []
            return
        }
        
        // Capture the trashed items on the main thread before going to background
        let itemsToCheck = Array(trashedItems)
        
        // Use fetchQueue to avoid blocking the main thread
        fetchQueue.async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", itemsToCheck)
            let fetchedAssets = PHAsset.fetchAssets(with: fetchOptions)
            
            // Process in batches to avoid creating large arrays
            var assets: [PHAsset] = []
            assets.reserveCapacity(fetchedAssets.count)
            
            // Track missing identifiers
            var existingIdentifiers = Set<String>()
            existingIdentifiers.reserveCapacity(fetchedAssets.count)
            
            // Process in batches
            let totalCount = fetchedAssets.count
            
            // Skip if no assets to process
            if totalCount == 0 {
                Task { @MainActor in
                    self.trashedMediaAssets = []
                }
                return
            }
            
            // Use a local copy of pageSize to avoid actor isolation issues
            let localPageSize = self.pageSize
            let batchSize = max(1, min(localPageSize, totalCount)) // Ensure at least 1 to avoid zero stride
            
            // Use our utility class for batch processing
            PHAssetBatchProcessor.processBatched(fetchResult: fetchedAssets, batchSize: batchSize) { asset in
                assets.append(asset)
                existingIdentifiers.insert(asset.localIdentifier)
            }
            
            // Calculate non-existent identifiers
            let nonExistentIdentifiers = Set(itemsToCheck).subtracting(existingIdentifiers)
            
            // Update on main thread
            Task { @MainActor in
                // Remove identifiers for assets that no longer exist
                if !nonExistentIdentifiers.isEmpty {
                    self.trashedItems.subtract(nonExistentIdentifiers)
                    self.saveTrashedItems()
                }
                
                self.trashedMediaAssets = assets
            }
        }
    }
}

// Photo library change observer implementation
extension SwipedMediaManager: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task {
            let assetsToCheck = await MainActor.run { self.trashedMediaAssets }
            
            var needsUpdate = false
            
            for asset in assetsToCheck {
                if let details = changeInstance.changeDetails(for: asset),
                   details.objectWasDeleted {
                    needsUpdate = true
                    break
                }
            }
            
            if needsUpdate {
                await MainActor.run {
                    self.updateTrashedMediaAssets()
                    self.categoryProgressCache.removeAll()
                    self.yearProgressCache.removeAll()
                    self.albumProgressCache.removeAll()
                }
                
                await ProgressManager.shared.invalidateCache()
            }
        }
    }
}
