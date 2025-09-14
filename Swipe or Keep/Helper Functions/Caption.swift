import SwiftUI
import Photos

struct Caption: View {
    let mediaSize: String
    let date: String
    let asset: PHAsset
    let shareButton: AnyView
    let swipeDirection: SwipeDirection?
    let isMuted: Bool?  // New: mute state for videos
    let onMuteToggle: (() -> Void)?  // New: mute toggle callback
    
    @State private var isLiked = false
    @State private var heartScale: CGFloat = 1.0
    @State private var showParticles = false
    @State private var particleOpacity: Double = 0.0
    
    // Format the date into "MMMM d, yyyy"
    private var formattedDate: String {
        let inputFormatter = DateFormatter()
        let formats = [
            "MMM d, yyyy","MMM dd, yyyy",
            "MMMM d, yyyy","MMMM dd, yyyy",
            "M/d/yyyy","MM/dd/yyyy","yyyy-MM-dd"
        ]
        for f in formats {
            inputFormatter.dateFormat = f
            if let d = inputFormatter.date(from: date) {
                let out = DateFormatter(); out.dateFormat = "MMMM d, yyyy"
                return out.string(from: d)
            }
        }
        return date
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // —— bottom‑left info
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mediaSize)
                                .font(.custom(AppFont.regular, size: 24))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                            Text(formattedDate)
                                .font(.custom(AppFont.regular, size: 15))
                                .foregroundColor(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                

                
                // —— bottom‑right buttons + swipe icon
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        // increased spacing between groups
                        VStack(spacing: 24) {
                            // —— Like button + label
                            VStack(spacing: 4) {
                                ZStack {
                                    if showParticles {
                                        ForEach(0..<8) { i in
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.red)
                                                .opacity(particleOpacity)
                                                .offset(
                                                    x: cos(Double(i) * .pi/4) * 30,
                                                    y: sin(Double(i) * .pi/4) * 30
                                                )
                                                .scaleEffect(0.5)
                                        }
                                    }
                                    Button { handleLikeAction() } label: {
                                        Image(systemName: isLiked ? "heart.fill" : "heart")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundColor(isLiked ? .red : .white)
                                            .scaleEffect(heartScale)
                                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                                    }
                                }
                                Text("Like")
                                    .font(.custom(AppFont.regular, size: 12))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                            
                            // —— Share button + label
                            VStack(spacing: 4) {
                                shareButton
                                    .frame(width: 48, height: 48)
                                Text("Share")
                                    .font(.custom(AppFont.regular, size: 12))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                            
                            // —— Mute button + label (only for videos)
                            if asset.mediaType == .video, let muted = isMuted, let toggle = onMuteToggle {
                                VStack(spacing: 4) {
                                    Button(action: toggle) {
                                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 48, height: 48)
                                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                                    }
                                    Text(muted ? "Unmute" : "Mute")
                                        .font(.custom(AppFont.regular, size: 12))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                }
                            }
                            
                            // —— Swipe‑feedback icon
                            if let dir = swipeDirection {
                                Image(systemName: dir == .right
                                      ? "hand.thumbsup.fill"
                                      : "trash.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(dir == .right ? .green : .red)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(.bottom, 120)
                        .padding(.trailing, 20)
                    }
                }
            }
        }
        .onAppear { updateLikeState() }
        .onChange(of: asset.localIdentifier, initial: true) {
            updateLikeState()
            heartScale = 1.0
            showParticles = false
            particleOpacity = 0.0
        }
    }
    
    private func updateLikeState() {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: nil)
        if let updated = fetch.firstObject { isLiked = updated.isFavorite }
    }
    
    private func handleLikeAction() {
        let willLike = !isLiked
        toggleFavoriteStatus(for: asset.localIdentifier, desiredState: willLike)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            isLiked = willLike
            heartScale = willLike ? 1.4 : 1.0
            showParticles = willLike
            particleOpacity = willLike ? 1.0 : 0.0
        }
        if willLike {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    heartScale = 1.0
                    showParticles = false
                    particleOpacity = 0.0
                }
            }
        }
        UIImpactFeedbackGenerator(style: willLike ? .heavy : .light).impactOccurred()
    }
    
    private func toggleFavoriteStatus(for localIdentifier: String, desiredState: Bool) {
        PHPhotoLibrary.shared().performChanges({
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            if let obj = fetch.firstObject {
                PHAssetChangeRequest(for: obj).isFavorite = desiredState
            }
        }, completionHandler: nil)
    }
}

// MARK: – Convenience inits

extension Caption {
    // For images (no mute controls)
    init(mediaSize: String, date: String, asset: PHAsset, swipeDirection: SwipeDirection? = nil) {
        self.mediaSize = mediaSize
        self.date = date
        self.asset = asset
        self.shareButton = AnyView(ShareButton(asset: asset))
        self.swipeDirection = swipeDirection
        self.isMuted = nil
        self.onMuteToggle = nil
    }
    
    // For videos (with mute controls)
    init(mediaSize: String, date: String, asset: PHAsset, swipeDirection: SwipeDirection? = nil, isMuted: Bool, onMuteToggle: @escaping () -> Void) {
        self.mediaSize = mediaSize
        self.date = date
        self.asset = asset
        self.shareButton = AnyView(ShareButton(asset: asset))
        self.swipeDirection = swipeDirection
        self.isMuted = isMuted
        self.onMuteToggle = onMuteToggle
    }
    
    init<ShareView: View>(
        mediaSize: String,
        date: String,
        asset: PHAsset,
        swipeDirection: SwipeDirection? = nil,
        shareButton: ShareView,
        isMuted: Bool? = nil,
        onMuteToggle: (() -> Void)? = nil
    ) {
        self.mediaSize = mediaSize
        self.date = date
        self.asset = asset
        self.shareButton = AnyView(shareButton)
        self.swipeDirection = swipeDirection
        self.isMuted = isMuted
        self.onMuteToggle = onMuteToggle
    }
}

#Preview {
    ZStack {
        LinearGradient(
            gradient: Gradient(colors: [.blue, .purple, .pink]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        Caption(
            mediaSize: "12.4 MB",
            date: "Dec 15, 2024",
            asset: PHAsset(), // placeholder
            shareButton: AnyView(
                Button(action: {}) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
            ),
            isMuted: true,
            onMuteToggle: { print("Mute toggled") }
        )
    }
}
