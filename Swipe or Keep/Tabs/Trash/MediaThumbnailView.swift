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

struct MediaThumbnailView: View {
    let asset: PHAsset
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    let size: CGFloat  // Dynamic size passed in

    @State private var thumbnail: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false

    private var targetSize: CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: size * scale, height: size * scale)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                                    .font(.custom(AppFont.regular, size: 20))
                                    .foregroundColor(.white)
                            }
                        }
                } else {
                    Rectangle()
                        .fill(Color(UIColor.systemGray6))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .overlay(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.blue, lineWidth: 3)
                    }
                }
            )
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)

            if asset.mediaType == .video {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill").font(.caption)
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

            if isSelectionMode {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.black.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? Color.blue.opacity(0.8) : Color.white.opacity(0.7), lineWidth: 2)
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

        if cache.isLoading(key: key) {
            return
        }

        if let cachedImage = cache.getImage(for: key) {
            self.thumbnail = cachedImage
            return
        }

        cache.setLoading(key: key, isLoading: true)
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            manager.requestImage(for: asset,
                                  targetSize: targetSize,
                                  contentMode: .aspectFill,
                                  options: options) { result, info in

                cache.setLoading(key: key, isLoading: false)

                if let result = result, let info = info, info[PHImageResultIsDegradedKey] as? Bool == false {
                    cache.setImage(result, for: key)
                    DispatchQueue.main.async {
                        self.thumbnail = result
                        self.isLoading = false
                        self.loadFailed = false
                    }
                } else if result == nil {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.loadFailed = true
                    }
                }
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
