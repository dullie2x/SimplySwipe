import SwiftUI
import Photos

// Your ThumbnailCache class
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

// Updated MediaThumbnailView with theme colors
struct MediaThumbnailView: View {
    let asset: PHAsset
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void

    @State private var thumbnail: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    
    // Theme colors based on the app's design
    private let gradientStart = Color(red: 0.2, green: 0.6, blue: 0.3) // Green
    private let gradientEnd = Color(red: 0.2, green: 0.4, blue: 0.8) // Blue
    
    // Scale based on screen scale factor to ensure proper resolution
    private let targetSize: CGSize = {
        let scale = UIScreen.main.scale
        return CGSize(width: 300 * scale, height: 300 * scale)
    }()
    
    // Dynamic height for thumbnail
    private var thumbnailHeight: CGFloat {
        return 130
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Media thumbnail
            Group {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if isLoading {
                    Rectangle()
                        .fill(Color(UIColor.systemGray6))
                        .overlay {
                            ProgressView()
                                .tint(.white)
                        }
                } else if loadFailed {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 24))
                                
                                Text("Tap to retry")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                }
                else {
                    Rectangle()
                        .fill(Color(UIColor.systemGray6))
                }
            }
            .frame(height: thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(colors: [gradientStart, gradientEnd]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    }
                }
            )
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            
            // Media type indicator (video/image)
            if asset.mediaType == .video {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.caption)
                    
                    Text(timeString(from: asset.duration))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.6))
                .cornerRadius(6)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .foregroundColor(.white)
            }
            
            // Selection checkmark
            if isSelectionMode {
                ZStack {
                    Circle()
                        .fill(isSelected ? gradientEnd : Color.black.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? gradientStart : Color.white.opacity(0.7), lineWidth: 2)
                        )
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    }
                }
                .padding(6)
            }
        }
        .onTapGesture {
            if loadFailed {
                // Retry on tap if failed
                loadFailed = false
                loadThumbnail()
            } else {
                onTap()
                hapticFeedback(style: .light)
            }
        }
        .onAppear {
            loadThumbnail()
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
    
    private func timeString(from seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
