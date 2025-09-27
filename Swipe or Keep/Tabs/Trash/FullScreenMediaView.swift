import SwiftUI
import Photos
import AVKit
import AVFoundation

struct FullScreenMediaView: View {
    let initialAsset: PHAsset
    let allAssets: [PHAsset]
    let onClose: () -> Void

    @State private var currentIndex: Int
    @State private var displayedImages: [UIImage?]
    @State private var videoPlayers: [Int: AVPlayer]
    @State private var isLoadingFullRes: [Bool]
    @State private var loadFailed: [Bool]
    @State private var audioSessionConfigured: Bool = false
    
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
                            .font(.custom(AppFont.regular, size: 12))
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
                        .clipped() // Improves swiping performance
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentIndex) // Smoother transitions
                .onChange(of: currentIndex) { _, newIndex in
                    // Preload adjacent media when index changes
                    preloadMediaAroundIndex(newIndex)
                    
                    // Pause all other videos when switching
                    for (playerIndex, player) in videoPlayers {
                        if playerIndex != newIndex {
                            player.pause()
                        }
                    }
                }
                
                // Bottom bar with date
                HStack {
                    // Date and video info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(allAssets[currentIndex].creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown Date")
                            .font(.custom(AppFont.regular, size: 12))
                            .foregroundColor(.white)
                        
                        if currentIndex < allAssets.count, allAssets[currentIndex].mediaType == .video {
                            Text(timeString(from: allAssets[currentIndex].duration))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color.black.opacity(0.6))
            }
        }
        .onAppear {
            configureAudioSession()
            // Preload media when view appears
            preloadMediaAroundIndex(currentIndex)
        }
        .onDisappear {
            // Clean up video players when view disappears
            NotificationCenter.default.removeObserver(self)
            
            for (_, player) in videoPlayers {
                player.pause()
            }
            videoPlayers.removeAll()
            
            // Reset audio session
            resetAudioSession()
        }
    }
    
    // Configure audio session for video playback
    private func configureAudioSession() {
        guard !audioSessionConfigured else { return }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Set category with options that allow audio to play even in silent mode
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP, .duckOthers]
            )
            
            // Activate the session with high priority
            try audioSession.setActive(true, options: [])
            audioSessionConfigured = true
            print("✅ Audio session configured for video playback")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }
    
    // Reset audio session when leaving
    private func resetAudioSession() {
        if audioSessionConfigured {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                audioSessionConfigured = false
                print("Audio session deactivated")
            } catch {
                print("Failed to deactivate audio session: \(error)")
            }
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
                        .font(.custom(AppFont.regular, size: 20))
                        .foregroundColor(.white)
                    
                    Button("Retry") {
                        loadFailed[index] = false
                        loadImage(for: index)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
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
    
    // Video player component using default iOS VideoPlayer
    private func videoPlayerView(for index: Int) -> some View {
        ZStack {
            if let player = videoPlayers[index] {
                VideoPlayer(player: player)
                    .id("video-\(index)-\(allAssets[index].localIdentifier)") // Unique ID to prevent reuse
                    .onAppear {
                        // Auto-play when video becomes visible and is current
                        if index == currentIndex {
                            player.seek(to: .zero) // Reset to beginning
                            player.play()
                        }
                    }
                    .onChange(of: currentIndex) { _, newCurrentIndex in
                        // Handle focus change
                        if index == newCurrentIndex {
                            // This video is now focused - play it
                            player.seek(to: .zero) // Reset to beginning
                            player.play()
                        } else {
                            // This video is no longer focused - pause it
                            player.pause()
                        }
                    }
            } else if loadFailed[index] {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    
                    Text("Failed to load video")
                        .font(.custom(AppFont.regular, size: 20))
                        .foregroundColor(.white)
                    
                    Button("Retry") {
                        loadFailed[index] = false
                        // Clear any existing player first
                        if let existingPlayer = videoPlayers[index] {
                            existingPlayer.pause()
                            videoPlayers.removeValue(forKey: index)
                        }
                        loadVideo(for: index)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
                    .onAppear {
                        // Only load if we don't already have a player or it's not already loading
                        if videoPlayers[index] == nil && !loadFailed[index] {
                            loadVideo(for: index)
                        }
                    }
            }
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
    
    // Load video for playback - Updated to use standard AVPlayer
    private func loadVideo(for index: Int) {
        let asset = allAssets[index]
        guard asset.mediaType == .video else { return }
        
        // Check if we already have a player for this index
        guard videoPlayers[index] == nil else { return }
        
        let manager = PHImageManager.default()
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        
        manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
            DispatchQueue.main.async {
                // Double-check we still don't have a player (avoid race conditions)
                guard videoPlayers[index] == nil else { return }
                
                if let playerItem = playerItem {
                    let player = AVPlayer(playerItem: playerItem)
                    
                    // Configure the player
                    player.actionAtItemEnd = .none // Let VideoPlayer handle looping
                    player.automaticallyWaitsToMinimizeStalling = true
                    
                    // Enable external playback
                    player.allowsExternalPlayback = true
                    player.usesExternalPlaybackWhileExternalScreenIsActive = true
                    
                    // Store the player
                    videoPlayers[index] = player
                } else {
                    loadFailed[index] = true
                }
            }
        }
    }
    
    // Format time string for video duration
    private func timeString(from seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
