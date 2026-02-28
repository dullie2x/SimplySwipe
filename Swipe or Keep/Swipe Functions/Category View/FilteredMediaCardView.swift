import SwiftUI
import AVKit
import Photos

struct FilteredMediaCardView: View {
    let asset: PHAsset
    let size: CGSize
    let offset: CGSize
    let onSwiped: (SwipeDirection) -> Void
    let player: AVQueuePlayer?
    let highQualityImage: UIImage?
    let lowQualityImage: UIImage?
    let isCurrentlyFocused: Bool
    @Binding var isMuted: Bool
    let zoomScale: CGFloat
    let zoomOffset: CGSize

    // Loading state tracking
    @State private var mediaState: MediaItemState?
    @State private var stateCheckTimer: Timer?

    // Actual rendered size of the asset within the card (accounts for letterboxing)
    private var assetSize: CGSize {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return size }
        let assetAspect = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        let frameAspect = size.width / size.height
        if assetAspect > frameAspect {
            return CGSize(width: size.width, height: size.width / assetAspect)
        } else {
            return CGSize(width: size.height * assetAspect, height: size.height)
        }
    }
    private let cacheManager = CacheManager.shared

    // Computed properties for loading state
    private var hasError: Bool {
        if case .error = mediaState?.loadingState {
            return true
        }
        if case .networkError = mediaState?.loadingState {
            return true
        }
        if case .timeoutError = mediaState?.loadingState {
            return true
        }
        return false
    }

    // Only show error overlay when there's truly nothing to display
    private var shouldShowError: Bool {
        // For images: only show error if we have NO image at all
        if asset.mediaType == .image {
            return highQualityImage == nil && lowQualityImage == nil && hasError
        }

        // For videos: never block with full error overlay (poster frame is enough)
        // The user can still see what the video is and swipe on it
        return false
    }

    var body: some View {
        ZStack {
            Color.black
                .frame(width: size.width, height: size.height)

            Group {
                if asset.mediaType == .video {
                    videoContent
                } else {
                    imageContent
                }
            }
            .scaleEffect(zoomScale, anchor: .center)
            .offset(zoomOffset)

            // Swipe labels
            swipeLabels

            // Error overlay - only show when there's nothing to display
            if shouldShowError {
                errorOverlay
            }
        }
        .offset(offset)
        .onAppear {
            updateMediaState()
        }
        .onDisappear {
            stateCheckTimer?.invalidate()
            stateCheckTimer = nil
        }
        .onChange(of: isCurrentlyFocused) {
            if isCurrentlyFocused {
                updateMediaState()
            }
        }
    }

    // MARK: - Video Content

    private var videoContent: some View {
        ZStack {
            // Minimal background with subtle texture
            if let poster = highQualityImage ?? lowQualityImage {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .blur(radius: player == nil ? 20 : 0) // Blur while loading, sharp when ready
                    .opacity(player == nil ? 0.3 : 1.0) // Dim while loading
                    .animation(.easeOut(duration: 0.6), value: player != nil)
            } else {
                // Pure minimal fallback with loading indicator
                ThumbnailPlaceholder()
                    .frame(width: size.width, height: size.height)
            }

            // Show loading indicator when video player is loading
            if player == nil && (highQualityImage != nil || lowQualityImage != nil) {
                // Video player loading (we have thumbnail, waiting for player)
                ThumbnailPlaceholder()
            }

            // Video player (fades in smoothly when ready)
            if let player = player {
                TikTokVideoPlayerView(
                    player: player,
                    isFocused: isCurrentlyFocused
                )
                .frame(width: size.width, height: size.height)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Image Content

    private var imageContent: some View {
        Group {
            if let displayImage = highQualityImage ?? lowQualityImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
            } else {
                AsyncThumbnail(asset: asset, size: size)
            }
        }
    }

    // MARK: - Error Overlay

    @ViewBuilder
    private var errorOverlay: some View {
        if let state = mediaState {
            switch state.loadingState {
            case .networkError:
                NetworkErrorOverlay {
                    retryLoading()
                }

            case .error(let error):
                ErrorOverlay(error: error) {
                    retryLoading()
                }

            case .timeoutError:
                ErrorOverlay(error: NSError(
                    domain: "MediaCard",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Loading is taking longer than expected"]
                )) {
                    retryLoading()
                }

            default:
                EmptyView()
            }
        }
    }

    private func retryLoading() {
        updateMediaState()
    }

    // MARK: - Loading State

    private func updateMediaState() {
        mediaState = cacheManager.getMediaState(for: asset)

        // If still loading, poll for updates
        if let state = mediaState, state.loadingState == .loading {
            if stateCheckTimer == nil {
                stateCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
                    Task { @MainActor in
                        let newState = cacheManager.getMediaState(for: asset)
                        mediaState = newState

                        if newState.loadingState != .loading {
                            stateCheckTimer?.invalidate()
                            stateCheckTimer = nil
                        }
                    }
                }
            }
        } else {
            stateCheckTimer?.invalidate()
            stateCheckTimer = nil
        }
    }

    // MARK: - Labels

    private var swipeLabels: some View {
        ZStack {
            if offset.width > 50 {
                let opacity = Double(offset.width / 150).clamped(to: 0...1)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green.opacity(opacity), lineWidth: 50)
                    .blur(radius: 30)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green.opacity(opacity), lineWidth: 20)
                    .blur(radius: 10)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green.opacity(0.3 * opacity), lineWidth: 2)
            }
            if offset.width < -50 {
                let opacity = Double(-offset.width / 150).clamped(to: 0...1)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.red.opacity(opacity), lineWidth: 50)
                    .blur(radius: 30)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.red.opacity(opacity), lineWidth: 20)
                    .blur(radius: 10)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.red.opacity(0.3 * opacity), lineWidth: 2)
            }
        }
        .frame(width: assetSize.width + 40, height: assetSize.height + 40)
        .allowsHitTesting(false)
    }
}

// MARK: - Helpers

/// AsyncThumbnail ensures we ALWAYS show a thumbnail, even if cache hasn't loaded yet
struct AsyncThumbnail: View {
    let asset: PHAsset
    let size: CGSize

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
            } else {
                ThumbnailPlaceholder()
                    .frame(width: size.width, height: size.height)
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if let image = image {
                    Task { @MainActor in
                        self.thumbnail = image
                    }
                }
                continuation.resume()
            }
        }
    }
}

// MARK: - Swipe Label Preview

private struct FilteredSwipeLabelPreview: View {
    let offsetX: CGFloat
    let size: CGSize

    var body: some View {
        ZStack {
            Color.gray.opacity(0.3)
            Image(systemName: "photo")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.2))

            if offsetX > 50 {
                let opacity = Double(offsetX / 150).clamped(to: 0...1)
                HStack(spacing: 0) {
                    Spacer()
                    ZStack(alignment: .trailing) {
                        LinearGradient(
                            colors: [.clear, Color.green.opacity(0.85 * opacity)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        VStack(spacing: 8) {
                            Image(systemName: "hand.thumbsup.fill")
                                .font(.system(size: 44, weight: .bold))
                            Text("KEEP")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .opacity(opacity)
                        .padding(.trailing, 32)
                    }
                    .frame(width: size.width * 0.55)
                }
                .frame(width: size.width, height: size.height)
            }

            if offsetX < -50 {
                let opacity = Double(-offsetX / 150).clamped(to: 0...1)
                HStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        LinearGradient(
                            colors: [Color.red.opacity(0.85 * opacity), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        VStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 44, weight: .bold))
                            Text("DELETE")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .opacity(opacity)
                        .padding(.leading, 32)
                    }
                    .frame(width: size.width * 0.55)
                    Spacer()
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Filtered Swipe Labels") {
    let size = CGSize(width: 350, height: 600)
    VStack(spacing: 24) {
        Text("Neutral")
            .foregroundColor(.white).font(.caption)
        FilteredSwipeLabelPreview(offsetX: 0, size: size)

        Text("Keep (swipe right)")
            .foregroundColor(.white).font(.caption)
        FilteredSwipeLabelPreview(offsetX: 130, size: size)

        Text("Delete (swipe left)")
            .foregroundColor(.white).font(.caption)
        FilteredSwipeLabelPreview(offsetX: -130, size: size)
    }
    .padding()
    .background(Color.black)
}
