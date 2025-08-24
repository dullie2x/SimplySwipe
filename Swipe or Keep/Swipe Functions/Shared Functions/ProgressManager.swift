import Foundation
import Photos

// MARK: - Progress change notification
extension Notification.Name {
    static let progressDidChange = Notification.Name("progressDidChange")
}

// Actor for thread-safe progress cache management
actor ProgressManager {
    static let shared = ProgressManager()
    
    // Cache storage with timestamps to detect when recalculation is needed
    private var categoryProgressCache: [Int: (timestamp: Date, progress: Double)] = [:]
    private var yearProgressCache: [String: (timestamp: Date, progress: Double)] = [:]
    private var albumProgressCache: [String: (timestamp: Date, progress: Double)] = [:]
    
    // Cache freshness threshold (recalculate after 5 minutes)
    private let cacheFreshnessDuration: TimeInterval = 300 // 5 minutes
    
    private init() {}

    // MARK: - Categories (Recents, Screenshots, Favorites)
    func getCategoryProgress() async -> [Int: Double] {
        var results: [Int: Double] = [:]

        for index in 0..<3 {
            // Use cached value if still fresh
            if let cached = categoryProgressCache[index],
               Date().timeIntervalSince(cached.timestamp) < cacheFreshnessDuration {
                results[index] = cached.progress
                continue
            }

            // Map index → category
            let category: SwipedMediaManager.MediaCategory
            switch index {
            case 0: category = .recents
            case 1: category = .screenshots
            case 2: category = .favorites
            default: continue
            }

            // Calculate on main (SwipedMediaManager is @MainActor)
            let progress: Double = await MainActor.run {
                SwipedMediaManager.shared.calculateProgress(forCategory: category)
            }

            categoryProgressCache[index] = (Date(), progress)
            results[index] = progress
        }

        return results
    }

    // MARK: - Years / Month-Years (e.g., "2025" or "Jan '25")
    func getYearProgress(for years: [String]) async -> [String: Double] {
        guard !years.isEmpty else { return [:] }
        var results: [String: Double] = [:]

        await withTaskGroup(of: (String, Double).self) { group in
            for year in years {
                // Serve from cache if fresh
                if let cached = yearProgressCache[year],
                   Date().timeIntervalSince(cached.timestamp) < cacheFreshnessDuration {
                    results[year] = cached.progress
                    continue
                }

                group.addTask {
                    let progress: Double = await withCheckedContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            let isFullYear = year.count == 4 && Int(year) != nil

                            let fetchOptions = PHFetchOptions()
                            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                            let allAssets = PHAsset.fetchAssets(with: fetchOptions)

                            Task {
                                let swipedIdentifiers = await MainActor.run {
                                    SwipedMediaManager.shared.getSwipedMediaIdentifiers()
                                }

                                var totalCount = 0
                                var swipedCount = 0
                                let calendar = Calendar.current
                                let df = DateFormatter()
                                df.dateFormat = "MMM ''yy"

                                PHAssetBatchProcessor.processBatched(fetchResult: allAssets, batchSize: 500) { asset in
                                    guard let creationDate = asset.creationDate else { return }

                                    let matches: Bool
                                    if isFullYear {
                                        let assetYear = calendar.component(.year, from: creationDate)
                                        matches = String(assetYear) == year
                                    } else {
                                        let formatted = df.string(from: creationDate)
                                        matches = formatted == year
                                    }

                                    if matches {
                                        totalCount += 1
                                        if swipedIdentifiers.contains(asset.localIdentifier) {
                                            swipedCount += 1
                                        }
                                    }
                                }

                                let value = totalCount > 0 ? Double(swipedCount) / Double(totalCount) : 0.0
                                continuation.resume(returning: value)
                            }
                        }
                    }

                    return (year, progress)
                }
            }

            for await (year, progress) in group {
                yearProgressCache[year] = (Date(), progress)
                results[year] = progress
            }
        }

        return results
    }

    // MARK: - Albums
    func getAlbumProgress(for folders: [PHAssetCollection]) async -> [String: Double] {
        guard !folders.isEmpty else { return [:] }
        var results: [String: Double] = [:]

        await withTaskGroup(of: (String, Double).self) { group in
            for folder in folders {
                guard let title = folder.localizedTitle else { continue }

                // Cache hit
                if let cached = albumProgressCache[title],
                   Date().timeIntervalSince(cached.timestamp) < cacheFreshnessDuration {
                    results[title] = cached.progress
                    continue
                }

                group.addTask {
                    let progress: Double = await MainActor.run {
                        SwipedMediaManager.shared.calculateProgress(for: folder)
                    }
                    return (title, progress)
                }
            }

            for await (title, progress) in group {
                albumProgressCache[title] = (Date(), progress)
                results[title] = progress
            }
        }

        return results
    }

    // MARK: - Cache invalidation (+ notify UI to refresh)
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

        // Tell the app that progress changed so views can re-fetch immediately
        Task { @MainActor in
            NotificationCenter.default.post(name: .progressDidChange, object: nil)
        }
    }
}

// MARK: - PHAssetBatchProcessor (unchanged)
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
