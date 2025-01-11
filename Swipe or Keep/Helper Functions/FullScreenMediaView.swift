import SwiftUI
import Photos

struct FullScreenMediaView: View {
    let initialAsset: PHAsset
    let allAssets: [PHAsset]
    let onClose: () -> Void

    @State private var currentIndex: Int
    @State private var displayedImages: [UIImage?] // Preloaded images for smooth scrolling

    init(initialAsset: PHAsset, allAssets: [PHAsset], onClose: @escaping () -> Void) {
        self.initialAsset = initialAsset
        self.allAssets = allAssets
        self.onClose = onClose
        self._currentIndex = State(initialValue: allAssets.firstIndex(where: { $0.localIdentifier == initialAsset.localIdentifier }) ?? 0)
        self._displayedImages = State(initialValue: Array(repeating: nil, count: allAssets.count))
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all) // Background color

            VStack {
                // Top bar with only date and time
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .bold))
                    }
                    Spacer()
                    if let creationDate = allAssets[currentIndex].creationDate {
                        Text(creationDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.white)
                            .font(.subheadline)
                    } else {
                        Text("Unknown Date")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.black.opacity(0.8))

                // Image display with swipeable functionality
                TabView(selection: $currentIndex) {
                    ForEach(allAssets.indices, id: \.self) { index in
                        ZStack {
                            if let image = displayedImages[index] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ProgressView()
                                    .onAppear {
                                        loadThumbnailOrImage(for: index)
                                    }
                            }
                        }
                        .tag(index) // Tag for maintaining the index
                    }
                }
                .tabViewStyle(PageTabViewStyle())
            }
        }
    }

    // Helper function to load thumbnails or full-resolution images
    private func loadThumbnailOrImage(for index: Int) {
        let asset = allAssets[index]
        let cache = ThumbnailCache.shared
        let key = "\(asset.localIdentifier)-full" as NSString

        // Check if a full-resolution image is cached
        if let cachedImage = cache.object(forKey: key) {
            displayedImages[index] = cachedImage
            return
        }

        // Load a thumbnail first for smooth scrolling
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false

        manager.requestImage(for: asset,
                             targetSize: CGSize(width: 600, height: 600), // Moderate resolution for smooth scrolling
                             contentMode: .aspectFit,
                             options: options) { result, _ in
            if let result = result {
                DispatchQueue.main.async {
                    displayedImages[index] = result
                }

                // Load full-resolution image in the background
                loadFullResolutionImage(for: asset, index: index)
            }
        }
    }

    // Helper function to load full-resolution images asynchronously
    private func loadFullResolutionImage(for asset: PHAsset, index: Int) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        manager.requestImage(for: asset,
                             targetSize: PHImageManagerMaximumSize,
                             contentMode: .aspectFit,
                             options: options) { result, _ in
            if let result = result {
                let cache = ThumbnailCache.shared
                let key = "\(asset.localIdentifier)-full" as NSString
                cache.setObject(result, forKey: key) // Cache the full-resolution image

                DispatchQueue.main.async {
                    displayedImages[index] = result
                }
            }
        }
    }
}
