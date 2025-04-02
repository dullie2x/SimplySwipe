//
//  FilteredMediaCardView.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 3/9/25.
//

import SwiftUI
import Photos
import AVKit



struct FilteredMediaCardView: View {
    let asset: PHAsset
    let size: CGSize
    @Binding var offset: CGSize
    let onSwiped: (SwipeDirection) -> Void
    let player: AVQueuePlayer?
    let highQualityImage: UIImage?
    let lowQualityImage: UIImage?
    
    // Enhanced state variables for better error handling
    @State private var loadingState: MediaLoadingState = .loading
    @State private var loadAttempts = 0
    @State private var isMuted = true
    @State private var timeoutTask: DispatchWorkItem?
    
    // Constants
    private let maxRetryAttempts = 3
    private let timeoutDuration: TimeInterval = 8
    
    var body: some View {
        ZStack {
            // Base image layer - show highest quality available
            imageLayer
                .blur(radius: offset == .zero ? 0 : 10)
            
            // Handle video content
            if asset.mediaType == .video {
                videoLayer
            }

            // Swiping labels
            swipeLabels
        }
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation
                }
                .onEnded { _ in
                    handleSwipeEnd()
                }
        )
        .onDisappear {
            // Clean up resources
            timeoutTask?.cancel()
            player?.pause()
        }
    }
    
    // MARK: - View Components
    
    private var imageLayer: some View {
        Group {
            if let highQualityImage = highQualityImage {
                Image(uiImage: highQualityImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipped()
            } else if let lowQualityImage = lowQualityImage {
                Image(uiImage: lowQualityImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipped()
            } else {
                ProgressView()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
            }
        }
    }
    
    private var videoLayer: some View {
        Group {
            if case .loading = loadingState {
                loadingVideoView
            } else if let player = player, case .loaded = loadingState {
                videoPlayerView(player: player)
            } else {
                videoErrorView
            }
        }
    }
    
    private var loadingVideoView: some View {
        VStack(spacing: 15) {
            Image(systemName: "video.circle")
                .font(.system(size: 40))
                .foregroundColor(.white)
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Loading Video")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Attempt \(loadAttempts) of \(maxRetryAttempts)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(0.85))
        .onAppear {
            preloadVideo()
        }
    }
    
    private func videoPlayerView(player: AVQueuePlayer) -> some View {
        VideoPlayer(player: player)
            .frame(width: size.width, height: size.height)
            .onAppear {
                player.volume = 0.0
                isMuted = true
                player.play()
            }
            .onDisappear { player.pause() }
            .blur(radius: offset == .zero ? 0 : 10)
            .overlay(
                // Audio control button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        audioControlButton(player: player)
                        
                        // Add a playback control button
                        Button(action: {
                            if player.timeControlStatus == .playing {
                                player.pause()
                            } else {
                                player.play()
                            }
                            
                            // Add haptic feedback
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }) {
                            Image(systemName: player.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                                )
                        }
                        .padding(.trailing, 16)
                    }
                    .padding(.bottom, 16)
                }
            )
    }
    
    private func audioControlButton(player: AVQueuePlayer) -> some View {
        Button(action: {
            isMuted.toggle()
            player.volume = isMuted ? 0.0 : 1.0
            
            // Add haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                )
        }
        .padding(.horizontal, 16)
        .transition(.scale)
        .animation(.spring(), value: isMuted)
    }
    
    private var videoErrorView: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.9)
            
            VStack(spacing: 25) {
                // Dynamic icon based on error type
                Image(systemName: loadingState.systemImageName)
                    .font(.system(size: 55, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.3), radius: 4)
                
                VStack(spacing: 8) {
                    Text("Playback Issue")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Specific error message based on state
                    Text(getErrorDescription())
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                VStack(spacing: 12) {
                    // Only show retry if under max attempts
                    if loadAttempts < maxRetryAttempts {
                        Button(action: retryLoadingVideo) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Try Again")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.white)
                            )
                        }
                    }
                    
                    Button(action: { onSwiped(.skip) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Skip")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .strokeBorder(Color.white, lineWidth: 1.5)
                        )
                    }
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var swipeLabels: some View {
        Group {
            if offset.width > 0 {
                LabelView(text: "Keep", color: .green)
                    .opacity(Double(offset.width / 150).clamped(to: 0...1))
            } else if offset.width < 0 {
                LabelView(text: "Delete", color: .red)
                    .opacity(Double(-offset.width / 150).clamped(to: 0...1))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getErrorDescription() -> String {
        switch loadingState {
        case .error:
            return "This video couldn't be loaded. This could be due to file format or storage issues."
        case .networkError:
            return "Your connection appears to be offline. Please check your internet and try again."
        case .timeoutError:
            return "The video is taking too long to load. It may be too large or the server might be busy."
        default:
            return "Something went wrong while loading the video."
        }
    }
    
    private func handleSwipeEnd() {
        if offset.width > 100 {
            onSwiped(.right)
        } else if offset.width < -100 {
            onSwiped(.left)
        } else {
            withAnimation(.spring()) { offset = .zero }
        }
    }

    private func preloadVideo() {
        loadingState = .loading
        loadAttempts += 1
        
        // Cancel any existing timeout task
        timeoutTask?.cancel()
        
        // Create new timeout task
        timeoutTask = DispatchWorkItem {
            DispatchQueue.main.async {
                loadingState = .timeoutError
            }
        }
        
        // Schedule timeout
        if let timeoutTask = timeoutTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDuration, execute: timeoutTask)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = PHImageManager.default()
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            // Add error handler to detect network issues
            options.progressHandler = { progress, error, stop, info in
                if let error = error {
                    DispatchQueue.main.async {
                        if (error as NSError).domain == "NSURLErrorDomain" {
                            loadingState = .networkError
                        } else {
                            loadingState = .error(error)
                        }
                        timeoutTask?.cancel()
                    }
                    stop.pointee = true
                }
            }

            manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
                // Cancel the timeout since we got a response
                timeoutTask?.cancel()
                
                DispatchQueue.main.async {
                    if playerItem != nil {
                        loadingState = .loaded
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        loadingState = .error(error)
                    } else {
                        loadingState = .error(NSError(domain: "FilteredMediaCardViewError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video"]))
                    }
                }
            }
        }
    }
    
    private func retryLoadingVideo() {
        preloadVideo()
    }
}


