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
            
            // Use autoreleasepool to prevent memory buildup during large collection processing
            var mediaItems: [PHAsset] = []
            autoreleasepool {
                // Create a filtered list of non-swiped items
                let allItems = result.objects(at: IndexSet(integersIn: 0..<result.count))
                mediaItems = allItems.filter { !SwipedMediaManager.shared.isMediaSwiped($0) }
                mediaItems.shuffle()
            }
            
            let paginatedItems = Array(mediaItems.prefix(30))
            
            DispatchQueue.main.async {
                completion(paginatedItems, result.count)
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
    
    // Updated to call completion for each image rather than all at once
    // Make sure low-quality image fetching is very fast
    func prefetchLowQualityImages(for media: [PHAsset], completion: @escaping (Int, UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async { // Change to highest priority
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isSynchronous = false
            options.resizeMode = .fast // Prioritize speed
            
            // Process all thumbnails first as they're critical for UI responsiveness
            for (index, asset) in media.enumerated() {
                manager.requestImage(for: asset,
                                    targetSize: CGSize(width: 300, height: 300),
                                    contentMode: .aspectFill,
                                    options: options) { result, _ in
                    if let result = result {
                        DispatchQueue.main.async {
                            completion(index, result)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Video Management
    // Updated to process videos in batches and call completion for each video
    func preloadVideos(for media: [PHAsset], completion: @escaping (Int, AVQueuePlayer?, AVPlayerLooper?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let manager = PHImageManager.default()
            let options = PHVideoRequestOptions()
            options.deliveryMode = .mediumQualityFormat // Changed from highQuality to save memory
            options.isNetworkAccessAllowed = true
            
            // Find video assets
            let videoIndices = media.enumerated()
                .filter { $0.element.mediaType == .video }
                .map { $0.offset }
            
            // Process in smaller batches to avoid memory spikes
            let batchSize = 3 // Smaller batch size for videos as they use more memory
            for batchStart in stride(from: 0, to: videoIndices.count, by: batchSize) {
                autoreleasepool {
                    let batchEnd = min(batchStart + batchSize, videoIndices.count)
                    for i in batchStart..<batchEnd {
                        let index = videoIndices[i]
                        let asset = media[index]
                        
                        manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                            if let playerItem = playerItem {
                                DispatchQueue.main.async {
                                    let player = AVQueuePlayer(playerItem: playerItem)
                                    let looper = AVPlayerLooper(player: player, templateItem: playerItem)
                                    player.pause()
                                    player.volume = 0.0
                                    completion(index, player, looper)
                                }
                            } else {
                                DispatchQueue.main.async {
                                    completion(index, nil, nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
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
                    cachedPlayer.player.volume = 1.0
                } else {
                    cachedPlayer.player.pause()
                    cachedPlayer.player.volume = 0.0
                }
            }
        }
    }
    
    func initializeAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to initialize audio session: \(error)")
        }
    }
}
