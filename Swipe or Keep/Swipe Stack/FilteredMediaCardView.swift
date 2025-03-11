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
            }

            // **Handle Video Playback**
            if asset.mediaType == .video {
                if let player = player {
                    VideoPlayer(player: player)
                        .frame(width: size.width, height: size.height)
                        .onAppear { player.play() }
                        .onDisappear { player.pause() }
                        .blur(radius: offset == .zero ? 0 : 10)

                } else {
                    // **Loading Indicator for Unready Videos**
                    VStack {
                        ProgressView("Loading Video...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .foregroundColor(.white)
                    }
                    .frame(width: size.width, height: size.height)
                    .background(Color.black.opacity(0.8))
                    .onAppear {
                        preloadVideo()
                    }
                }
            }

            // **Swiping Labels**
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

    /// **Manually Triggers Video Preload if Not Ready**
    private func preloadVideo() {
        DispatchQueue.global(qos: .userInitiated).async {
            let manager = PHImageManager.default()
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                DispatchQueue.main.async {
                    if let playerItem = playerItem {
                        let player = AVQueuePlayer(playerItem: playerItem)
                        player.play()
                    }
                }
            }
        }
    }
}
