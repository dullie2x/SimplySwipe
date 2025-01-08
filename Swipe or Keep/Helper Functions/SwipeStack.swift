import SwiftUI
import Photos
import AVKit

struct SwipeStack: View {
    @State private var offset = CGSize.zero
    @State private var currentIndex = 0
    @State private var mediaItems: [PHAsset] = []
    @State private var paginatedMediaItems: [PHAsset] = []
    @State private var mediaSize: String = "0 MB"
    @State private var isLoading = true
    @State private var preloadedPlayers: [Int: (AVQueuePlayer, AVPlayerLooper?)] = [:]
    @State private var highQualityImages: [Int: UIImage] = [:] // Cache for high-quality images
    @State private var lowQualityImages: [Int: UIImage] = [:] // Cache for low-quality images

    private let pageSize = 30 // Limit to 30 media items -- ONLY FOR RANDOM

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Please Wait..")
                    .scaleEffect(1.5)
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        HStack {
                            Text("Size: \(mediaSize)")
                                .font(Font.title2.weight(.heavy))
                                .foregroundColor(.green)
                                .padding(8)
                                .onChange(of: currentIndex) {
                                    updateMediaSize() // Ensure real-time update
                                    fetchHighQualityImage(for: currentIndex) // Fetch high-quality image for current index
                                    fetchHighQualityImage(for: currentIndex + 1) // Preload high-quality image for the next media
                                    pauseNonFocusedVideos() // Pause non-focused videos
                                }
                            Spacer()
                            Text("\(currentIndex + 1)/\(mediaItems.count)")
                                .font(Font.title2.weight(.heavy))
                                .foregroundColor(.green)
                                .padding(8)
                        }
                        .padding(.horizontal, 20)
                        .zIndex(1)

                        ZStack {
                            ForEach(currentIndex..<min(currentIndex + 2, paginatedMediaItems.count), id: \ .self) { index in
                                if index < paginatedMediaItems.count {
                                    MediaCardView(
                                        asset: paginatedMediaItems[index],
                                        size: CGSize(width: geometry.size.width - CGFloat((index - currentIndex) * 15), height: geometry.size.height - CGFloat((index - currentIndex) * 15) - 60),
                                        offset: index == currentIndex ? $offset : .constant(.zero),
                                        onSwiped: handleSwipe,
                                        player: preloadedPlayers[index]?.0,
                                        highQualityImage: highQualityImages[index],
                                        lowQualityImage: lowQualityImages[index] // Pass low-quality image
                                    )
                                    .zIndex(Double(-index))
                                    .offset(x: CGFloat((index - currentIndex) * 10), y: CGFloat((index - currentIndex) * 10))
                                    .scaleEffect(index == currentIndex ? 1.0 : 0.95, anchor: .center)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.2), value: currentIndex) // Improved animation

                                }
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height - 60)
                        .zIndex(0)
                    }
                }
            }
        }
        .onAppear(perform: initializeAudioSession)
        .onAppear(perform: fetchMedia)
    }

    // Initialize Audio Session
    func initializeAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
    }

    // Fetch Media Items -- BI
    func fetchMedia() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
            fetchOptions.fetchLimit = 30

            let result = PHAsset.fetchAssets(with: fetchOptions)
            var tempMediaItems: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                tempMediaItems.append(asset)
            }

            DispatchQueue.main.async {
                self.mediaItems = tempMediaItems
                self.paginatedMediaItems = tempMediaItems
                self.updateMediaSize()
                self.preloadVideos()
                self.isLoading = false
                self.prefetchLowQualityImages() // Prefetch low-quality images
                self.fetchHighQualityImage(for: currentIndex) // Preload the first image in high quality
                self.fetchHighQualityImage(for: currentIndex + 1) // Preload the second image in high quality
            }
        }
    }

    // Preload Videos -- BI
    func preloadVideos() {
        DispatchQueue.global(qos: .background).async {
            for (index, asset) in self.paginatedMediaItems.enumerated() where asset.mediaType == .video {
                let manager = PHImageManager.default()
                let options = PHVideoRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true

                manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                    if let playerItem = playerItem {
                        DispatchQueue.main.async {
                            let player = AVQueuePlayer(playerItem: playerItem)
                            player.volume = index == self.currentIndex ? 1.0 : 0.0 // Adjust audio volume
                            let looper = AVPlayerLooper(player: player, templateItem: playerItem)
                            self.preloadedPlayers[index] = (player, looper)
                        }
                    }
                }
            }
        }
    }

    // Pause Non-Focused Videos
    func pauseNonFocusedVideos() {
        for (index, player) in preloadedPlayers {
            if index != currentIndex {
                player.0.pause()
                player.0.volume = 0.0 // Mute non-focused videos
            } else {
                player.0.play()
                player.0.volume = 1.0 // Enable audio for the current video
            }
        }
    }

    // Fetch High-Quality Image
    func fetchHighQualityImage(for index: Int) {
        guard index < paginatedMediaItems.count else { return }
        let asset = paginatedMediaItems[index]

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        manager.requestImage(for: asset, targetSize: CGSize(width: 1920, height: 1080), contentMode: .aspectFit, options: options) { result, _ in
            if let result = result {
                DispatchQueue.main.async {
                    self.highQualityImages[index] = result
                }
            }
        }
    }

    // Prefetch Low-Quality Images
    func prefetchLowQualityImages() {
        DispatchQueue.global(qos: .userInitiated).async {
            for (index, asset) in self.paginatedMediaItems.enumerated() {
                let manager = PHImageManager.default()
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.isSynchronous = true

                manager.requestImage(for: asset, targetSize: CGSize(width: 640, height: 360), contentMode: .aspectFit, options: options) { result, _ in
                    if let result = result {
                        DispatchQueue.main.async {
                            self.lowQualityImages[index] = result
                        }
                    }
                }
            }
        }
    }

    // Swipe Handling - BI
    func handleSwipe(direction: SwipeDirection) {
        if direction == .left {
            // Move the current item to the trash
            if currentIndex < paginatedMediaItems.count {
                let trashedItem = paginatedMediaItems[currentIndex]
                TrashManager.shared.addToTrash(trashedItem) // Add to trash using the shared manager
            }
        }

        // Trigger haptic feedback
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()

        withAnimation(.easeInOut(duration: 0.15)) { // Swipe animation
            offset.width = direction == .left ? -1000 : 1000
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { // Match animation duration
            offset = .zero
            currentIndex += 1 // Move to the next media
            if currentIndex < paginatedMediaItems.count {
                fetchHighQualityImage(for: currentIndex) // Load the next card's high-quality image
                fetchHighQualityImage(for: currentIndex + 1) // Preload the image after that
            }
            pauseNonFocusedVideos()
        }
    }



    // Media Size Handling - BI

    func updateMediaSize() {
        guard currentIndex < paginatedMediaItems.count else { return }
        let asset = paginatedMediaItems[currentIndex]
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            mediaSize = ByteCountFormatter.string(fromByteCount: Int64(resource.value(forKey: "fileSize") as? Int ?? 0), countStyle: .file)
        }
    }
}

// Updated MediaCardView -- BI
struct MediaCardView: View {
    let asset: PHAsset
    let size: CGSize
    @Binding var offset: CGSize
    let onSwiped: (SwipeDirection) -> Void
    let player: AVQueuePlayer?
    let highQualityImage: UIImage? // High-quality image passed
    let lowQualityImage: UIImage? // Low-quality image passed

    var body: some View {
        ZStack {
            if let highQualityImage = highQualityImage {
                Image(uiImage: highQualityImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipped()
                    .blur(radius: offset == .zero ? 0 : 10) // Add blur dynamically based on swipe offset
            } else if let lowQualityImage = lowQualityImage {
                Image(uiImage: lowQualityImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipped()
                    .blur(radius: offset == .zero ? 0 : 10) // Add blur dynamically based on swipe offset
            }

            if asset.mediaType == .video, let player = player {
                VideoPlayer(player: player)
                    .frame(width: size.width, height: size.height)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
                    .blur(radius: offset == .zero ? 0 : 10) // Add blur dynamically for videos
            }

            if offset.width > 0 {
                LabelView(text: "Keep", color: .green)
                    .opacity(Double(offset.width / 150).clamped(to: 0...1))
            } else if offset.width < 0 {
                LabelView(text: "Delete", color: .red)
                    .opacity(Double(-offset.width / 150).clamped(to: 0...1))
            }
        }
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation
                }
                .onEnded { _ in
                    if offset.width > 100 {
                        onSwiped(.right)
                    } else if offset.width < -100 {
                        onSwiped(.left)
                    } else {
                        withAnimation(.spring()) { offset = .zero }
                    }
                }
        )
    }
}

    private func getUIImage(from asset: PHAsset) -> UIImage {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat // Lower media quality
        options.isSynchronous = true

        var image = UIImage()
        manager.requestImage(for: asset, targetSize: CGSize(width: 640, height: 360), contentMode: .aspectFit, options: options) { result, _ in
            if let result = result {
                image = result
            }
        }
        return image
    }

enum SwipeDirection {
    case left, right
}

struct SwipeStack_Previews: PreviewProvider {
    static var previews: some View {
        SwipeStack()
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
