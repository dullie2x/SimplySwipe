import Foundation
import Photos

// Actor for thread-safe progress cache management
actor ProgressManager {
    static let shared = ProgressManager()
    
    // Cache storage with timestamps to detect when recalculation is needed
    private var categoryProgressCache: [Int: (timestamp: Date, progress: Double)] = [:]
    private var yearProgressCache: [String: (timestamp: Date, progress: Double)] = [:]
    private var albumProgressCache: [String: (timestamp: Date, progress: Double)] = [:]
    
    // Cache freshness threshold (recalculate after 5 minutes)
    private let cacheFreshnessDuration: TimeInterval = 300 // 5 minutes
    
    // Background calculation queue
    private let calculationQueue = DispatchQueue(label: "com.app.progressManager.calculation", qos: .utility)
    
    private init() {}
    
    // Get progress for categories (Recents, Screenshots, Favorites)
    func getCategoryProgress() async -> [Int: Double] {
        // Skip calculation if no swiped media
        let swipeCount = await MainActor.run { SwipedMediaManager.shared.swipeCount }
        if swipeCount == 0 {
            return [:]
        }
        
        var results: [Int: Double] = [:]
        
        for index in 0..<3 {
            // Check if we have a fresh cache entry
            if let cachedData = categoryProgressCache[index],
               Date().timeIntervalSince(cachedData.timestamp) < cacheFreshnessDuration {
                results[index] = cachedData.progress
                continue
            }
            
            // Otherwise calculate new value
            let category: SwipedMediaManager.MediaCategory
            switch index {
            case 0:
                category = .recents
            case 1:
                category = .screenshots
            case 2:
                category = .favorites
            default:
                continue
            }
            
            // Calculate progress in the background
            let progress = await withCheckedContinuation { continuation in
                calculationQueue.async {
                    let result = SwipedMediaManager.shared.calculateProgress(forCategory: category)
                    continuation.resume(returning: result)
                }
            }
            
            // Update cache and results
            categoryProgressCache[index] = (Date(), progress)
            results[index] = progress
        }
        
        return results
    }
    
    // Get progress for years
    func getYearProgress(for years: [String]) async -> [String: Double] {
        // Skip calculation if no swiped media
        let swipeCount = await MainActor.run { SwipedMediaManager.shared.swipeCount }
        if swipeCount == 0 || years.isEmpty {
            return [:]
        }
        
        var results: [String: Double] = [:]
        
        // Process years in parallel for better performance
        await withTaskGroup(of: (String, Double).self) { group in
            for year in years {
                // Check if we have a fresh cache entry
                if let cachedData = yearProgressCache[year],
                   Date().timeIntervalSince(cachedData.timestamp) < cacheFreshnessDuration {
                    results[year] = cachedData.progress
                    continue
                }
                
                // Otherwise calculate in parallel
                group.addTask {
                    let progress = await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            let result = SwipedMediaManager.shared.calculateProgress(forYear: year)
                            continuation.resume(returning: result)
                        }
                    }
                    return (year, progress)
                }
            }
            
            // Collect results from parallel tasks
            for await (year, progress) in group {
                yearProgressCache[year] = (Date(), progress)
                results[year] = progress
            }
        }
        
        return results
    }
    
    // Get progress for albums
    func getAlbumProgress(for folders: [PHAssetCollection]) async -> [String: Double] {
        // Skip calculation if no swiped media
        let swipeCount = await MainActor.run { SwipedMediaManager.shared.swipeCount }
        if swipeCount == 0 || folders.isEmpty {
            return [:]
        }
        
        var results: [String: Double] = [:]
        
        // Process albums in parallel for better performance
        await withTaskGroup(of: (String, Double).self) { group in
            for folder in folders {
                guard let title = folder.localizedTitle else { continue }
                
                // Check if we have a fresh cache entry
                if let cachedData = albumProgressCache[title],
                   Date().timeIntervalSince(cachedData.timestamp) < cacheFreshnessDuration {
                    results[title] = cachedData.progress
                    continue
                }
                
                // Otherwise calculate in parallel
                group.addTask {
                    let progress = await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            let result = SwipedMediaManager.shared.calculateProgress(for: folder)
                            continuation.resume(returning: result)
                        }
                    }
                    return (title, progress)
                }
            }
            
            // Collect results from parallel tasks
            for await (title, progress) in group {
                albumProgressCache[title] = (Date(), progress)
                results[title] = progress
            }
        }
        
        return results
    }
    
    // Method to invalidate all caches
    func invalidateCache(forYear year: String? = nil, forAlbum album: String? = nil, forCategory index: Int? = nil) {
        if let year = year {
            yearProgressCache.removeValue(forKey: year)
        } else if let album = album {
            albumProgressCache.removeValue(forKey: album)
        } else if let index = index {
            categoryProgressCache.removeValue(forKey: index)
        } else {
            // Invalidate all caches if no specific item is provided
            yearProgressCache.removeAll()
            albumProgressCache.removeAll()
            categoryProgressCache.removeAll()
        }
    }
}

// Instead of extending PHFetchResult, create a utility class for pagination
class PHAssetBatchProcessor {
    // Get a page of PHAssets from a fetch result
    static func getPage(from fetchResult: PHFetchResult<PHAsset>, offset: Int, pageSize: Int) -> [PHAsset] {
        var results: [PHAsset] = []
        let validOffset = max(0, offset)
        results.reserveCapacity(min(pageSize, fetchResult.count - validOffset))
        
        let endIndex = min(validOffset + pageSize, fetchResult.count)
        
        for i in validOffset..<endIndex {
            results.append(fetchResult.object(at: i))
        }
        
        return results
    }
    
    // Process PHAssets in batches
    static func processBatched(fetchResult: PHFetchResult<PHAsset>, batchSize: Int, processor: (PHAsset) -> Void) {
        let totalCount = fetchResult.count
        
        for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
            autoreleasepool {
                let batchEnd = min(batchStart + batchSize, totalCount)
                
                for i in batchStart..<batchEnd {
                    processor(fetchResult.object(at: i))
                }
            }
        }
    }
    
    // Count PHAssets that match a condition
    static func countMatching(fetchResult: PHFetchResult<PHAsset>, batchSize: Int, condition: (PHAsset) -> Bool) -> Int {
        let totalCount = fetchResult.count
        var matchCount = 0
        
        for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
            autoreleasepool {
                let batchEnd = min(batchStart + batchSize, totalCount)
                
                for i in batchStart..<batchEnd {
                    if condition(fetchResult.object(at: i)) {
                        matchCount += 1
                    }
                }
            }
        }
        
        return matchCount
    }
}
