import SwiftUI
import Photos
import AVKit

struct FullScreenMediaView: View {
    let initialAsset: PHAsset
    let allAssets: [PHAsset]
    let onClose: () -> Void

    @State private var currentIndex: Int
    @State private var displayedImages: [UIImage?]
    @State private var videoPlayers: [Int: AVPlayer]
    @State private var isLoadingFullRes: [Bool]
    @State private var loadFailed: [Bool]
    @State private var isMuted: Bool = false
    @State private var isPlaying: Bool = false
    
    // Timer for observing player status
    @State private var playerStatusTimer: Timer? = nil
    
    // Theme colors based on the app's design
    private let gradientStart = Color(red: 0.2, green: 0.6, blue: 0.3) // Green
    private let gradientEnd = Color(red: 0.2, green: 0.4, blue: 0.8) // Blue
    
    // Track visible indices for preloading
    @State private var visibleRange: Range<Int>? = nil

    init(initialAsset: PHAsset, allAssets: [PHAsset], onClose: @escaping () -> Void) {
        self.initialAsset = initialAsset
        self.allAssets = allAssets
        self.onClose = onClose
        self._currentIndex = State(initialValue: allAssets.firstIndex(where: { $0.localIdentifier == initialAsset.localIdentifier }) ?? 0)
        self._displayedImages = State(initialValue: Array(repeating: nil, count: allAssets.count))
        self._videoPlayers = State(initialValue: [:])
        self._isLoadingFullRes = State(initialValue: Array(repeating: false, count: allAssets.count))
        self._loadFailed = State(initialValue: Array(repeating: false, count: allAssets.count))
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Top bar with close button and info
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .padding(.leading, 8)
                    
                    Spacer()
                    
                    // Media counter
                    HStack(spacing: 8) {
                        Text("\(currentIndex + 1) of \(allAssets.count)")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    
                    Spacer()
                    
                    // Add a spacer with width equivalent to the back button for balance
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(Color.black.opacity(0.6))

                // Swipeable media viewer
                TabView(selection: $currentIndex) {
                    ForEach(allAssets.indices, id: \.self) { index in
                        ZStack {
                            if allAssets[index].mediaType == .video {
                                videoPlayerView(for: index)
                            } else {
                                imageView(for: index)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .onChange(of: currentIndex) { newIndex in
                    // Preload adjacent media when index changes
                    preloadMediaAroundIndex(newIndex)
                    
                    // Stop any playing videos that are no longer visible
                    for (playerIndex, player) in videoPlayers {
                        if playerIndex != newIndex {
                            player.pause()
                        }
                    }
                    
                    // Apply mute setting to the current video
                    if let player = videoPlayers[newIndex] {
                        player.isMuted = isMuted
                    }
                }
                
                // Bottom bar with date and controls
                HStack {
                    // Date and video info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(allAssets[currentIndex].creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown Date")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        
                        // Fixed: Remove the 'safe:' label
                        if currentIndex < allAssets.count, allAssets[currentIndex].mediaType == .video {
                            Text(timeString(from: allAssets[currentIndex].duration))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Video controls - Fixed: Remove the 'safe:' label
                    if currentIndex < allAssets.count, allAssets[currentIndex].mediaType == .video, let player = videoPlayers[currentIndex] {
                        HStack(spacing: 20) {
                            // Play/Pause button
                            Button(action: {
                                if isPlaying {
                                    player.pause()
                                    isPlaying = false
                                } else {
                                    player.play()
                                    isPlaying = true
                                }
                            }) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                            }
                            
                            // Mute button
                            Button(action: {
                                isMuted.toggle()
                                player.isMuted = isMuted
                            }) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
            }
        }
        .onAppear {
            // Preload media when view appears
            preloadMediaAroundIndex(currentIndex)
        }
        .onDisappear {
            // Clean up video players when view disappears
            stopObservingPlayerStatus()
            
            // Remove observer and clean up players
            NotificationCenter.default.removeObserver(self)
            
            for (_, player) in videoPlayers {
                player.pause()
            }
            videoPlayers.removeAll()
        }
    }
    
    // Image view component
    private func imageView(for index: Int) -> some View {
        ZStack {
            if let image = displayedImages[index] {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .overlay(
                            isLoadingFullRes[index] ?
                                AnyView(ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.7)
                                    .padding(6)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .position(x: 40, y: 40)
                                ) :
                                AnyView(EmptyView())
                        )
                }
            } else if loadFailed[index] {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    
                    Text("Failed to load image")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Button("Retry") {
                        loadFailed[index] = false
                        loadImage(for: index)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(LinearGradient(
                        gradient: Gradient(colors: [gradientStart, gradientEnd]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                    .onAppear {
                        loadImage(for: index)
                    }
            }
        }
    }
    
    // Video player component
    private func videoPlayerView(for index: Int) -> some View {
        ZStack {
            if let player = videoPlayers[index] {
                CustomVideoPlayer(player: player)
                    .onAppear {
                        // Apply mute setting
                        player.isMuted = isMuted
                        
                        // Start observing player status
                        startObservingPlayerStatus(player)
                        
                        // Automatically play the video when it becomes visible
                        player.play()
                        isPlaying = true
                    }
                    .onDisappear {
                        // Pause the video when it's no longer visible
                        player.pause()
                        isPlaying = false
                        
                        // Stop observing when disappearing
                        stopObservingPlayerStatus()
                    }
            } else if loadFailed[index] {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    
                    Text("Failed to load video")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Button("Retry") {
                        loadFailed[index] = false
                        loadVideo(for: index)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(LinearGradient(
                        gradient: Gradient(colors: [gradientStart, gradientEnd]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                    .onAppear {
                        loadVideo(for: index)
                    }
            }
        }
    }
    
    // Custom video player without default controls
    struct CustomVideoPlayer: UIViewControllerRepresentable {
        let player: AVPlayer
        
        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.showsPlaybackControls = false
            controller.videoGravity = .resizeAspect
            return controller
        }
        
        func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
            uiViewController.player = player
        }
    }
    
    // Preload media around the current index
    private func preloadMediaAroundIndex(_ index: Int) {
        let preloadRadius = 1 // How many items to preload in each direction
        let start = max(0, index - preloadRadius)
        let end = min(allAssets.count, index + preloadRadius + 1)
        
        for i in start..<end {
            let asset = allAssets[i]
            
            if asset.mediaType == .video {
                if videoPlayers[i] == nil && !loadFailed[i] {
                    loadVideo(for: i)
                }
            } else {
                if displayedImages[i] == nil && !loadFailed[i] {
                    loadImage(for: i)
                }
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
    
    // Load video for playback
    private func loadVideo(for index: Int) {
        let asset = allAssets[index]
        guard asset.mediaType == .video else { return }
        
        let manager = PHImageManager.default()
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        
        manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
            DispatchQueue.main.async {
                if let playerItem = playerItem {
                    let player = AVPlayer(playerItem: playerItem)
                    
                    // Configure the player
                    player.actionAtItemEnd = .pause
                    player.automaticallyWaitsToMinimizeStalling = true
                    player.isMuted = isMuted
                    
                    // Add observer for when item finishes playing
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: playerItem,
                        queue: .main
                    ) { _ in
                        isPlaying = false
                    }
                    
                    // Store the player
                    videoPlayers[index] = player
                    
                    // Start playing if this is the current index
                    if index == currentIndex {
                        player.play()
                        isPlaying = true
                        startObservingPlayerStatus(player)
                    }
                } else {
                    loadFailed[index] = true
                }
            }
        }
    }
    
    // Helper method to start observing player status
    private func startObservingPlayerStatus(_ player: AVPlayer) {
        // Cancel any existing timer
        stopObservingPlayerStatus()
        
        // Create a new timer to check player status
        playerStatusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            // Update playing state based on player status
            if player.timeControlStatus == .playing && !isPlaying {
                isPlaying = true
            } else if player.timeControlStatus != .playing && isPlaying {
                isPlaying = false
            }
        }
    }
    
    // Helper method to stop observing player status
    private func stopObservingPlayerStatus() {
        playerStatusTimer?.invalidate()
        playerStatusTimer = nil
    }
    
    // Format time string for video duration
    private func timeString(from seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

//// Extension to safely access array elements
//extension Array {
//    subscript(safe index: Index) -> Element? {
//        return indices.contains(index) ? self[index] : nil
//    }
//}
