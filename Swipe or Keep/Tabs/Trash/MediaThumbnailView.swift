import SwiftUI
import Photos

class ThumbnailCache {
    static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let loadingOperations = NSCache<NSString, NSNumber>()
    
    private init() {
        // Configure cache limits
        cache.countLimit = 300  // Max number of images to cache
        cache.totalCostLimit = 50 * 1024 * 1024  // Limit cache to ~50MB
    }
    
    func getImage(for key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func setImage(_ image: UIImage, for key: String) {
        // Calculate approximate memory size as cost (width * height * 4 bytes)
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    // Track which assets are already being loaded to avoid duplicate requests
    func isLoading(key: String) -> Bool {
        return loadingOperations.object(forKey: key as NSString) != nil
    }
    
    func setLoading(key: String, isLoading: Bool) {
        if isLoading {
            loadingOperations.setObject(1 as NSNumber, forKey: key as NSString)
        } else {
            loadingOperations.removeObject(forKey: key as NSString)
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        loadingOperations.removeAllObjects()
    }
}

struct MediaThumbnailView: View {
    let asset: PHAsset
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void

    @State private var thumbnail: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    
    // Scale based on screen scale factor to ensure proper resolution
    private let targetSize: CGSize = {
        let scale = UIScreen.main.scale
        return CGSize(width: 200 * scale, height: 200 * scale)
    }()

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(8)
            } else if isLoading {
                // Show spinner while loading
                ProgressView()
                    .frame(width: 100, height: 100)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
            } else if loadFailed {
                // Show error visual if load failed
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 100, height: 100)
                        .cornerRadius(8)
                    
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.yellow)
                        .font(.system(size: 24))
                }
                .onTapGesture {
                    // Retry on tap if failed
                    loadFailed = false
                    loadThumbnail()
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 100, height: 100)
                    .cornerRadius(8)
                    .onAppear {
                        loadThumbnail()
                    }
            }

            // Checkmark overlay in Selection Mode
            if isSelectionMode && isSelected {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 24, height: 24)
                        .offset(x: 35, y: -35)

                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .offset(x: 35, y: -35)
                }
            }
        }
        .onTapGesture {
            onTap()
        }
    }

    private func loadThumbnail() {
        let cache = ThumbnailCache.shared
        let key = asset.localIdentifier
        
        // Check if already being loaded
        if cache.isLoading(key: key) {
            return
        }

        // Check if the thumbnail is already cached
        if let cachedImage = cache.getImage(for: key) {
            self.thumbnail = cachedImage
            return
        }
        
        // Mark as loading and update UI
        cache.setLoading(key: key, isLoading: true)
        isLoading = true

        // Fetch the thumbnail on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic // Get fast image first, then higher quality if needed
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            manager.requestImage(for: asset,
                                targetSize: targetSize,
                                contentMode: .aspectFill,
                                options: options) { result, info in
                
                // Mark as no longer loading
                cache.setLoading(key: key, isLoading: false)
                
                if let result = result, let info = info, info[PHImageResultIsDegradedKey] as? Bool == false {
                    // Only cache and display the final (non-degraded) image
                    cache.setImage(result, for: key)
                    
                    DispatchQueue.main.async {
                        self.thumbnail = result
                        self.isLoading = false
                        self.loadFailed = false
                    }
                } else if result == nil {
                    // Handle failure case
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.loadFailed = true
                    }
                }
                // Note: If this is a degraded (low-res) image, we'll get another callback with the high-res version
            }
        }
    }
}
