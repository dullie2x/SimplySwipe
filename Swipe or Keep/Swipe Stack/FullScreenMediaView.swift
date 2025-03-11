import SwiftUI
import Photos

struct FullScreenMediaView: View {
    let initialAsset: PHAsset
    let allAssets: [PHAsset]
    let onClose: () -> Void

    @State private var currentIndex: Int
    @State private var displayedImages: [UIImage?]
    @State private var isLoadingFullRes: [Bool]
    @State private var loadFailed: [Bool]
    
    // Track visible indices for preloading
    @State private var visibleRange: Range<Int>? = nil

    init(initialAsset: PHAsset, allAssets: [PHAsset], onClose: @escaping () -> Void) {
        self.initialAsset = initialAsset
        self.allAssets = allAssets
        self.onClose = onClose
        self._currentIndex = State(initialValue: allAssets.firstIndex(where: { $0.localIdentifier == initialAsset.localIdentifier }) ?? 0)
        self._displayedImages = State(initialValue: Array(repeating: nil, count: allAssets.count))
        self._isLoadingFullRes = State(initialValue: Array(repeating: false, count: allAssets.count))
        self._loadFailed = State(initialValue: Array(repeating: false, count: allAssets.count))
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack {
                // Top bar with close button and date
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white)
                            .font(.system(size: 20, weight: .bold))
                    }
                    Spacer()
                    Text(allAssets[currentIndex].creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown Date")
                        .foregroundColor(.white)
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(Color.black.opacity(0.8))

                // Swipeable image viewer
                TabView(selection: $currentIndex) {
                    ForEach(allAssets.indices, id: \.self) { index in
                        ZStack {
                            if let image = displayedImages[index] {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .overlay(
                                        isLoadingFullRes[index] ?
                                            AnyView(ProgressView().scaleEffect(0.7).position(x: 40, y: 40)) :
                                            AnyView(EmptyView())
                                    )
                            } else if loadFailed[index] {
                                VStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 40))
                                        .foregroundColor(.yellow)
                                    Text("Loading failed")
                                        .foregroundColor(.white)
                                    Button("Retry") {
                                        loadFailed[index] = false
                                        loadImage(for: index)
                                    }
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            } else {
                                ProgressView()
                                    .onAppear {
                                        loadImage(for: index)
                                    }
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle())
                .onChange(of: currentIndex) { newIndex in
                    // Preload adjacent images when index changes
                    preloadImagesAroundIndex(newIndex)
                }
            }
        }
        .onAppear {
            // Preload images when view appears
            preloadImagesAroundIndex(currentIndex)
        }
    }
    
    // Preload images around the current index
    private func preloadImagesAroundIndex(_ index: Int) {
        let preloadRadius = 2 // How many images to preload in each direction
        let start = max(0, index - preloadRadius)
        let end = min(allAssets.count, index + preloadRadius + 1)
        
        for i in start..<end {
            if displayedImages[i] == nil && !loadFailed[i] {
                loadImage(for: i)
            }
        }
    }

    // Load image with two-phase loading (medium quality then full res)
    private func loadImage(for index: Int) {
        let asset = allAssets[index]
        
        // Check if we already have a cached full-res version
        let fullResKey = "\(asset.localIdentifier)-full"
        if let cachedImage = ThumbnailCache.shared.getImage(for: fullResKey) {
            displayedImages[index] = cachedImage
            return
        }
        
        // Check if we have a cached medium-res version
        let mediumResKey = "\(asset.localIdentifier)-medium"
        if let cachedImage = ThumbnailCache.shared.getImage(for: mediumResKey) {
            displayedImages[index] = cachedImage
            // Also load full-res in background
            loadFullImage(for: asset, index: index)
            return
        }
        
        // Load medium quality first for quick display
        let manager = PHImageManager.default()
        let mediumOptions = PHImageRequestOptions()
        mediumOptions.deliveryMode = .opportunistic
        mediumOptions.resizeMode = .exact
        mediumOptions.isSynchronous = false
        mediumOptions.isNetworkAccessAllowed = true
        
        // Calculate target size based on screen size
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * UIScreen.main.scale,
            height: UIScreen.main.bounds.height * UIScreen.main.scale
        )
        
        manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: mediumOptions
        ) { result, info in
            let degraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
            
            if let result = result {
                // Cache and display medium quality image
                ThumbnailCache.shared.setImage(result, for: mediumResKey)
                
                DispatchQueue.main.async {
                    // Only update if we don't already have a better image
                    if displayedImages[index] == nil {
                        displayedImages[index] = result
                    }
                    
                    // If this was just a preview, load full quality
                    if degraded {
                        loadFullImage(for: asset, index: index)
                    }
                }
            } else if result == nil && !degraded {
                // Failed to load image
                DispatchQueue.main.async {
                    loadFailed[index] = true
                }
            }
        }
    }

    // Load full-resolution image asynchronously
    private func loadFullImage(for asset: PHAsset, index: Int) {
        let fullResKey = "\(asset.localIdentifier)-full"
        
        // Skip if we're already loading or have the full-res image
        if isLoadingFullRes[index] || ThumbnailCache.shared.getImage(for: fullResKey) != nil {
            return
        }
        
        // Mark as loading full resolution
        DispatchQueue.main.async {
            isLoadingFullRes[index] = true
        }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true // Ensures loading works for iCloud photos

        manager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if let result = result {
                // Cache full-resolution image
                ThumbnailCache.shared.setImage(result, for: fullResKey)

                DispatchQueue.main.async {
                    displayedImages[index] = result
                    isLoadingFullRes[index] = false
                }
            } else {
                DispatchQueue.main.async {
                    isLoadingFullRes[index] = false
                    // Don't mark as failed since we already have the medium quality image
                }
            }
        }
    }
}
