import SwiftUI
import Photos
import AVKit

struct FilteredSwipeStack: View {
    @State private var offset = CGSize.zero
    @State private var currentIndex = 0
    @State private var mediaItems: [PHAsset] = []
    @State private var paginatedMediaItems: [PHAsset] = []
    @State private var mediaSize: String = "0 MB"
    @State private var isLoading = true
    @State private var loadingProgress: Double = 0.0 // Progress tracking
    @State private var preloadedPlayers: [Int: (AVQueuePlayer, AVPlayerLooper?)] = [:]
    @State private var highQualityImages: [Int: UIImage] = [:] // Cache for high-quality images
    @State private var lowQualityImages: [Int: UIImage] = [:] // Cache for low-quality images
    @Environment(\.presentationMode) var presentationMode // To handle navigation

    private let pageSize = 30 // Limit to 30 media items -- ONLY FOR FILTERED

    var filterOptions: PHFetchOptions

    var body: some View {
        VStack(spacing: 10) { // Add custom back button and reduce spacing
            // Custom Back Button
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss() // Navigate back
                }) {
                    Image(systemName: "arrow.left.circle") // Back arrow inside a circle
                        .resizable()
                        .frame(width: 30, height: 30) // Adjust the size of the icon
                        .foregroundColor(.white) // White color for the icon
                }
                .padding(.leading, 15) // Add some padding to the left
                .padding(.top, 10) // Add top padding for alignment
                Spacer()
            }

            ZStack {
                if isLoading {
                    VStack {
                        ProgressView("Loading Media...", value: loadingProgress, total: 1.0)
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                            .padding()
                        Text("\(Int(loadingProgress * 100))%")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                } else if currentIndex >= mediaItems.count {
                    VStack {
                        Text("All Done! :)")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                            .padding()
                    }
                } else {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            HStack {
                                Text("Size: \(mediaSize)")
                                    .font(Font.title2.weight(.heavy))
                                    .foregroundColor(.green)
                                    .padding(8)
                                    .onChange(of: currentIndex) { _ in
                                        updateMediaSize()
                                        fetchHighQualityImage(for: currentIndex, completion: nil)
                                        fetchHighQualityImage(for: currentIndex + 1, completion: nil)
                                        pauseNonFocusedVideos()
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
                                ForEach(currentIndex..<min(currentIndex + 2, paginatedMediaItems.count), id: \.self) { index in
                                    if index < paginatedMediaItems.count {
                                        FilteredMediaCardView(
                                            asset: paginatedMediaItems[index],
                                            size: CGSize(width: geometry.size.width - CGFloat((index - currentIndex) * 15), height: geometry.size.height - CGFloat((index - currentIndex) * 15) - 60),
                                            offset: index == currentIndex ? $offset : .constant(.zero),
                                            onSwiped: handleSwipe,
                                            player: preloadedPlayers[index]?.0,
                                            highQualityImage: highQualityImages[index],
                                            lowQualityImage: lowQualityImages[index]
                                        )
                                        .zIndex(Double(-index))
                                        .offset(x: CGFloat((index - currentIndex) * 10), y: CGFloat((index - currentIndex) * 10))
                                        .scaleEffect(index == currentIndex ? 1.0 : 0.95, anchor: .center)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.2), value: currentIndex)
                                    }
                                }
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height - 60)
                            .zIndex(0)
                        }
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea()) // Black background for the entire view
        .onAppear(perform: initializeAudioSession)
        .onAppear(perform: fetchFilteredMedia)
        .navigationBarHidden(true) // Hide the default navigation bar
    }

    func initializeAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
    }

    func fetchFilteredMedia() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PHAsset.fetchAssets(with: filterOptions)
            var tempMediaItems: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                tempMediaItems.append(asset)
            }

            DispatchQueue.main.async {
                if tempMediaItems.isEmpty {
                    self.isLoading = false
                    self.loadingProgress = 1.0
                    print("No media items found.")
                    return
                }

                self.mediaItems = tempMediaItems
                self.paginatedMediaItems = tempMediaItems
                self.updateMediaSize()
                self.prefetchLowQualityImages()
                self.preloadFirstFewItems()
            }
        }
    }

    func preloadFirstFewItems() {
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()

            for (index, asset) in self.mediaItems.prefix(3).enumerated() {
                group.enter()
                if asset.mediaType == .video {
                    preloadVideo(for: index, asset: asset) {
                        group.leave()
                    }
                } else {
                    fetchHighQualityImage(for: index) {
                        group.leave()
                    }
                }
                DispatchQueue.main.async {
                    self.loadingProgress = Double(index + 1) / 3.0
                }
            }

            group.notify(queue: .main) {
                self.isLoading = false
                self.preloadRemainingItems()
            }
        }
    }

    func preloadRemainingItems() {
        DispatchQueue.global(qos: .background).async {
            for (index, asset) in self.mediaItems.dropFirst(3).enumerated() {
                if asset.mediaType == .video {
                    preloadVideo(for: index + 3, asset: asset, completion: nil)
                } else {
                    fetchHighQualityImage(for: index + 3, completion: nil)
                }
            }
        }
    }

    func preloadVideo(for index: Int, asset: PHAsset, completion: (() -> Void)?) {
        let manager = PHImageManager.default()
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            if let playerItem = playerItem {
                DispatchQueue.main.async {
                    let player = AVQueuePlayer(playerItem: playerItem)
                    player.volume = index == self.currentIndex ? 1.0 : 0.0
                    let looper = AVPlayerLooper(player: player, templateItem: playerItem)
                    self.preloadedPlayers[index] = (player, looper)
                }
            }
            completion?()
        }
    }

    func pauseNonFocusedVideos() {
        for (index, player) in preloadedPlayers {
            if index != currentIndex {
                player.0.pause()
                player.0.volume = 0.0
            } else {
                player.0.play()
                player.0.volume = 1.0
            }
        }
    }

    func fetchHighQualityImage(for index: Int, completion: (() -> Void)?) {
        guard index < paginatedMediaItems.count else {
            completion?()
            return
        }

        let asset = paginatedMediaItems[index]
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        manager.requestImage(for: asset, targetSize: CGSize(width: 1920, height: 1080), contentMode: .aspectFit, options: options) { result, info in
            if let result = result {
                DispatchQueue.main.async {
                    self.highQualityImages[index] = result
                }
            }
            completion?()
        }
    }

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

    func handleSwipe(direction: SwipeDirection) {
        if currentIndex < paginatedMediaItems.count {
            let currentItem = paginatedMediaItems[currentIndex]

            if direction == .left {
                SwipedMediaManager.shared.addSwipedMedia(currentItem, toTrash: true)
            } else if direction == .right {
                SwipedMediaManager.shared.addSwipedMedia(currentItem, toTrash: false)
            }

            // Stop playback of the current video's player
            if let player = preloadedPlayers[currentIndex]?.0 {
                player.pause()
                player.volume = 0.0
            }
        }

        // Trigger haptic feedback
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()

        withAnimation(.easeInOut(duration: 0.15)) {
            offset.width = direction == .left ? -1000 : 1000
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            offset = .zero
            currentIndex += 1

            pauseNonFocusedVideos() // Ensure only the current video plays
        }
    }

    func updateMediaSize() {
        guard currentIndex < paginatedMediaItems.count else { return }
        let asset = paginatedMediaItems[currentIndex]
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            mediaSize = ByteCountFormatter.string(fromByteCount: Int64(resource.value(forKey: "fileSize") as? Int ?? 0), countStyle: .file)
        }
    }
}

struct FilteredMediaCardView: View {
    let asset: PHAsset
    let size: CGSize
    @Binding var offset: CGSize
    let onSwiped: (SwipeDirection) -> Void
    let player: AVQueuePlayer?
    let highQualityImage: UIImage?
    let lowQualityImage: UIImage?

    var body: some View {
        ZStack {
            if let highQualityImage = highQualityImage {
                Image(uiImage: highQualityImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipped()
                    .blur(radius: offset == .zero ? 0 : 10)
            } else if let lowQualityImage = lowQualityImage {
                Image(uiImage: lowQualityImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipped()
                    .blur(radius: offset == .zero ? 0 : 10)
            }

            if asset.mediaType == .video, let player = player {
                VideoPlayer(player: player)
                    .frame(width: size.width, height: size.height)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
                    .blur(radius: offset == .zero ? 0 : 10)
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

struct FilteredSwipeStack_Previews: PreviewProvider {
    static var previews: some View {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)

        return FilteredSwipeStack(filterOptions: fetchOptions)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
