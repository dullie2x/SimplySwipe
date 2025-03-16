import SwiftUI
import Photos
import AVKit

struct MediaCardView: View {
    let asset: PHAsset
    let size: CGSize
    @Binding var offset: CGSize
    let onSwiped: (SwipeDirection) -> Void
    let player: AVQueuePlayer?
    let highQualityImage: UIImage?
    let lowQualityImage: UIImage?
    
    // Add state variables to track video loading state and mute status
    @State private var videoLoadError = false
    @State private var isLoadingVideo = false
    @State private var loadAttempts = 0
    @State private var isMuted = true
    
    var body: some View {
        ZStack {
            // Show High-Quality Image First
            if let highQualityImage = highQualityImage {
                Image(uiImage: highQualityImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipped()
                    .blur(radius: offset == .zero ? 0 : 10)

            // Otherwise, Show Low-Quality Image (Backup)
            } else if let lowQualityImage = lowQualityImage {
                Image(uiImage: lowQualityImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipped()
                    .blur(radius: offset == .zero ? 0 : 10)
            } else {
                ProgressView()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
            }

            // Handle Video Playback
            if asset.mediaType == .video {
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(width: size.width, height: size.height)
                        .onAppear {
                            // Explicitly set volume to 0 when the player appears
                            player.volume = 0.0
                            isMuted = true  // Make sure UI state matches
                            player.play()
                            videoLoadError = false
                            isLoadingVideo = false
                        }
                        .onDisappear { player.pause() }
                        .blur(radius: offset == .zero ? 0 : 10)
                        .overlay(
                            // Add mute/unmute button
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        isMuted.toggle()
                                        // Explicitly set volume to either 0 or 1
                                        if isMuted {
                                            player.volume = 0.0
                                        } else {
                                            player.volume = 1.0
                                        }
                                    }) {
                                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(.white)
                                            .padding(12)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                    .padding(16)
                                }
                            }
                        )
                } else if videoLoadError {
                    // Show retry/skip buttons when video fails to load
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.yellow)
                        
                        Text("Video failed to load")
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 30) {
                            Button(action: {
                                retryLoadingVideo()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.green.opacity(0.7))
                                )
                            }
                            
                            Button(action: {
                                // Skip this media item
                                onSwiped(.left)
                            }) {
                                HStack {
                                    Image(systemName: "forward.fill")
                                    Text("Skip")
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.blue.opacity(0.7))
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.7))
                } else {
                    // Loading Indicator for Unready Videos
                    VStack {
                        ProgressView("Loading Video...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .foregroundColor(.white)
                    }
                    .frame(width: size.width, height: size.height)
                    .background(Color.black.opacity(0.8))
                    .onAppear {
                        if !isLoadingVideo {
                            preloadVideo()
                        }
                    }
                }
            }

            // Swiping Labels
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

    /// Manually Triggers Video Preload if Not Ready
    private func preloadVideo() {
        isLoadingVideo = true
        loadAttempts += 1
        
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = PHImageManager.default()
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            // Set a timeout to show error UI if video doesn't load
            let timeoutTask = DispatchWorkItem {
                if isLoadingVideo {
                    DispatchQueue.main.async {
                        videoLoadError = true
                        isLoadingVideo = false
                    }
                }
            }
            
            // Schedule timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutTask)

            manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
                // Cancel the timeout since we got a response
                timeoutTask.cancel()
                
                DispatchQueue.main.async {
                    isLoadingVideo = false
                    
                    if let playerItem = playerItem {
                        let player = AVQueuePlayer(playerItem: playerItem)
                        // Ensure it's definitely muted initially
                        player.volume = 0.0
                        player.play()
                        videoLoadError = false
                    } else {
                        // Only mark as error if we've tried a few times
                        videoLoadError = true
                    }
                }
            }
        }
    }
    
    /// Function to retry loading a video that failed
    private func retryLoadingVideo() {
        videoLoadError = false
        isLoadingVideo = false
        preloadVideo()
    }
}

// Make `clamped(to:)` Publicly Available
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}


