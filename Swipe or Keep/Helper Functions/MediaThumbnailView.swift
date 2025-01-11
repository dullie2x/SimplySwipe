import SwiftUI
import Photos

class ThumbnailCache {
    static let shared = NSCache<NSString, UIImage>() // Shared cache instance
}

struct MediaThumbnailView: View {
    let asset: PHAsset
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill() // Fills the square frame while maintaining aspect ratio
                    .frame(width: 100, height: 100) // Fixed universal size for the thumbnail
                    .clipped() // Crops any overflowing parts of the image
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray)
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
        let key = asset.localIdentifier as NSString

        // Check if the thumbnail is already cached
        if let cachedImage = cache.object(forKey: key) {
            thumbnail = cachedImage
            return
        }

        // Fetch the thumbnail and cache it
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // Request high-quality images
        options.resizeMode = .exact // Ensures images match the requested size
        options.isSynchronous = false // Allow asynchronous fetching

        manager.requestImage(for: asset,
                             targetSize: CGSize(width: 300, height: 300), // Higher resolution target
                             contentMode: .aspectFill,
                             options: options) { result, _ in
            if let result = result {
                cache.setObject(result, forKey: key) // Cache the image
                DispatchQueue.main.async {
                    self.thumbnail = result // Update the UI
                }
            }
        }
    }
}
