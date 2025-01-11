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
    @State private var showBatchExhaustedNotice = false // Tracks if the notice should be displayed
    @State private var swipeCount = UserDefaults.standard.integer(forKey: "swipeCount") // Persistent swipe counter
    @State private var totalMediaCount = 0 // Total media on the device
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
                            //Text("\(swipeCount)/\(totalMediaCount)")
                            Text("Swipe Count: \(swipeCount)")

                                .font(Font.title2.weight(.heavy))
                                .foregroundColor(.green)
                                .padding(8)

                        }
                        .padding(.horizontal, 20)
                        .zIndex(1)

                        ZStack {
                            ForEach(currentIndex..<min(currentIndex + 2, paginatedMediaItems.count), id: \.self) { index in
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

            // Batch Exhausted Notice - will make better later
            if showBatchExhaustedNotice {
                VStack(spacing: 20) {
                    Text("You've gone through 30 media items.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()

                    Text("Would you like to fetch another batch? Consider clearing your trash to free up space.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()

                    Button("Okay") {
                        showBatchExhaustedNotice = false
                        fetchMedia() // Fetch the next batch
                    }
                    .padding()
                    .background(Color.green.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .frame(maxWidth: 300)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(20)
                .shadow(radius: 10)
                .transition(.opacity) // Smooth appearance/disappearance
                .zIndex(1) // Ensure it's above other views
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
        mediaItems = [] // Clear current media items to force UI refresh
        paginatedMediaItems = [] // Clear paginated items to reset the swipe stack

        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

            // Fetch all media
            let result = PHAsset.fetchAssets(with: fetchOptions)
            var tempMediaItems: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                // Exclude previously swiped media
                if !SwipedMediaManager.shared.isMediaSwiped(asset) {
                    tempMediaItems.append(asset)
                }
            }

            // Shuffle the media items to randomize them
            tempMediaItems.shuffle()

            // Limit to page size for paginated items
            let paginatedItems = Array(tempMediaItems.prefix(self.pageSize))

            DispatchQueue.main.async {
                self.mediaItems = tempMediaItems // Update the full media list
                self.paginatedMediaItems = paginatedItems // Update the current paginated stack
                self.totalMediaCount = result.count // Update the total count dynamically
                self.currentIndex = 0 // Reset the index for the new batch
                self.isLoading = false // Hide the loading indicator
                self.updateMediaSize() // Update the size information
                self.preloadVideos() // Preload videos for the new batch
                self.prefetchLowQualityImages() // Prefetch low-quality images for the new batch
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
                            if self.preloadedPlayers[index] == nil {
                                let player = AVQueuePlayer(playerItem: playerItem)
                                let looper = AVPlayerLooper(player: player, templateItem: playerItem)
                                self.preloadedPlayers[index] = (player, looper)

                                // Ensure the player is paused initially
                                player.pause()
                                player.volume = 0.0
                            }
                        }
                    }
                }
            }
        }
    }



    // Pause Non-Focused Videos
    func pauseNonFocusedVideos() {
        for (index, player) in preloadedPlayers {
            if index == currentIndex {
                // Play the video for the current index
                player.0.play()
                player.0.volume = 1.0
            } else {
                // Pause all other videos
                player.0.pause()
                player.0.volume = 0.0
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
        options.isNetworkAccessAllowed = true // Ensure network-based assets can be fetched
        options.resizeMode = .exact
        options.isSynchronous = false

        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 1920, height: 1080), // Full HD resolution
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            if let result = result {
                DispatchQueue.main.async {
                    self.highQualityImages[index] = result
                }
            } else if let info = info, (info[PHImageErrorKey] as? NSError) != nil {
                print("Error fetching high-quality image for index \(index): \(info)")
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

    // Swipe Handling

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

        // Increment swipe count and save it
        swipeCount += 1
        UserDefaults.standard.set(swipeCount, forKey: "swipeCount")

        // Trigger haptic feedback
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()

        withAnimation(.easeInOut(duration: 0.15)) {
            offset.width = direction == .left ? -1000 : 1000
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            offset = .zero
            currentIndex += 1

            if currentIndex < paginatedMediaItems.count {
                fetchHighQualityImage(for: currentIndex)
                fetchHighQualityImage(for: currentIndex + 1)
            } else {
                handleBatchExhausted()
            }

            pauseNonFocusedVideos() // Ensure only the current video plays
        }
    }





    func handleBatchExhausted() {
        showBatchExhaustedNotice = true
        isLoading = false // Stop showing the spinner
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
            } else {
                // Always display the low-quality image if high-quality isn't ready
                if let lowQualityImage = lowQualityImage {
                    Image(uiImage: lowQualityImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .background(Color.black)
                        .clipped()
                        .blur(radius: offset == .zero ? 0 : 10) // Add blur dynamically based on swipe offset
                } else {
                    // Placeholder or fallback in case neither image is ready
                    ProgressView()
                        .frame(width: size.width, height: size.height)
                        .background(Color.black)
                }
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
