import Photos
import UIKit
import AVKit

class MediaManager {
    static let shared = MediaManager()
    
    private init() {}
    
    // MARK: - Media Fetching
    func fetchMedia(completion: @escaping ([PHAsset], Int) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: fetchOptions)
            
            // Use autoreleasepool for memory management
            var allItems: [PHAsset] = []
            autoreleasepool {
                allItems = result.objects(at: IndexSet(integersIn: 0..<result.count))
            }
            
            // Move only the filtering & shuffling to the main thread
            DispatchQueue.main.async {
                let mediaItems = allItems.filter { !SwipedMediaManager.shared.isMediaSwiped($0) }
                let shuffledMedia = mediaItems.shuffled()
                completion(shuffledMedia, result.count)
            }
        }
    }
    
    
    func updateMediaSize(for media: [PHAsset], index: Int) -> String {
        guard index < media.count else { return "0 MB" }
        let asset = media[index]
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            return ByteCountFormatter.string(fromByteCount: Int64(resource.value(forKey: "fileSize") as? Int ?? 0), countStyle: .file)
        }
        return "0 MB"
    }
    
    // MARK: - Image Fetching
    func fetchHighQualityImage(for index: Int, in media: [PHAsset], completion: @escaping (Int, UIImage?) -> Void) {
        guard index < media.count else {
            completion(index, nil)
            return
        }
        
        let asset = media[index]
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        
        // Reduced from 1920x1080 to 1080x1080 to save memory while maintaining quality
        manager.requestImage(for: asset,
                             targetSize: CGSize(width: 1080, height: 1080),
                             contentMode: .aspectFit,
                             options: options) { result, _ in
            DispatchQueue.main.async {
                completion(index, result)
            }
        }
    }

    // MARK: - Video Management
    
    // Updated to work with NSCache
    func pauseNonFocusedVideos(players: NSCache<NSNumber, CachedPlayer>, currentIndex: Int) {
        // We'll only check nearby indices to avoid unnecessary work
        for offset in -2...4 { // Check 2 behind and 4 ahead
            let index = currentIndex + offset
            guard index >= 0 else { continue }
            
            let indexNumber = NSNumber(value: index)
            if let cachedPlayer = players.object(forKey: indexNumber) {
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
}
