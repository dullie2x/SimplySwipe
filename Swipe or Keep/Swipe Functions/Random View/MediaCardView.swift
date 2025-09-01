import SwiftUI
import AVKit
import Photos

struct MediaCardView: View {
    let asset: PHAsset
    let size: CGSize
    let offset: CGSize
    let onSwiped: (SwipeDirection) -> Void
    let player: AVQueuePlayer?
    let highQualityImage: UIImage?
    let lowQualityImage: UIImage?
    let isCurrentlyFocused: Bool

    // Image crossfade state (prevents flicker)
    @State private var showHQImage = false

    var body: some View {
        ZStack {
            Color.black
                .frame(width: size.width, height: size.height)

            if asset.mediaType == .video {
                videoContent
            } else {
                imageContent
            }

            swipeLabels
        }
        .offset(offset)
        // When a new HQ image arrives, fade it in smoothly
        .onChange(of: highQualityImage) { newValue in
            if newValue != nil { showHQImage = true }
        }
    }

    // MARK: - Video

    private var videoContent: some View {
        Group {
            if let player = player {
                ZStack {
                    // Poster while video prepares; stays .fit to show full frame
                    if let poster = highQualityImage ?? lowQualityImage {
                        Image(uiImage: poster)
                            .resizable()
                            .scaledToFit()
                            .frame(width: size.width, height: size.height)
                            .background(Color.black)
                            // Keep poster visible until player view is on top; no animation needed here
                    }

                    // Your video view (ensure its internal layer uses .resizeAspect if you want full frame)
                    TikTokVideoPlayerView(
                        player: player,
                        isFocused: isCurrentlyFocused
                    )
                    .frame(width: size.width, height: size.height)
                }
            } else {
                videoLoadingView
            }
        }
    }

    private var videoLoadingView: some View {
        ZStack {
            Color.black.opacity(0.8)
            // Time-driven bounce that auto-resumes after backgrounding
            BouncingLogo(size: 100, amplitude: 10, period: 0.9)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Image

    private var imageContent: some View {
        ZStack {
            // Base: show whatever is available first (LQ)
            if let low = lowQualityImage {
                Image(uiImage: low)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
            } else if highQualityImage == nil {
                // Nothing yet → loader
                imageLoadingView
            }

            // Fade in HQ image when it arrives (no transition identity swap)
            if let high = highQualityImage {
                Image(uiImage: high)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .opacity(showHQImage ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showHQImage)
            }
        }
    }

    private var imageLoadingView: some View {
        ZStack {
            Color.black
            BouncingLogo(size: 100, amplitude: 10, period: 0.9)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Labels

    private var swipeLabels: some View {
        Group {
            if offset.width > 50 {
                LabelView(text: "Keep", color: .green)
                    .opacity(Double(offset.width / 150).clamped(to: 0...1))
            } else if offset.width < -50 {
                LabelView(text: "Delete", color: .red)
                    .opacity(Double(-offset.width / 150).clamped(to: 0...1))
            }
        }
    }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

/// Time-driven bouncing logo that keeps animating across app lifecycle events.
private struct BouncingLogo: View {
    var size: CGFloat = 100
    var amplitude: CGFloat = 10       // vertical travel (pts)
    var period: Double = 0.9          // seconds per full cycle

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let y = sin((2 * .pi / period) * t) * amplitude

            Image("orca7")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .offset(y: y)
        }
    }
}
