import SwiftUI
import AVKit
import Photos

struct TikTokVideoPlayerView: View {
    let player: AVQueuePlayer
    let isFocused: Bool

    @State private var isPaused = false
    @State private var isReady = false
    @State private var hasError = false
    @State private var didSetup = false

    @StateObject private var playerObserver = VideoPlayerObserver()

    // MARK: - Setup / Teardown

    private func setupPlayer() {
        guard !didSetup else { return }
        didSetup = true

        playerObserver.startObserving(
            player: player,
            onItemChange: {
                // New item: reset and recheck readiness
                self.isReady = false
                self.hasError = false
                self.checkPlayerReadiness()
            },
            onStatusChange: { status in
                switch status {
                case .readyToPlay:
                    self.isReady = true
                    self.hasError = false
                    self.updatePlaybackState()
                case .failed:
                    if let err = self.player.currentItem?.error {
                        print("❌ Player item failed: \(err.localizedDescription)")
                    }
                    self.hasError = true
                    self.isReady = false
                case .unknown:
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.checkPlayerReadiness()
                    }
                @unknown default:
                    self.hasError = true
                }
            }
        )

        checkPlayerReadiness()
    }

    private func cleanupPlayer() {
        playerObserver.stopObserving()
        player.volume = 0.0
        player.pause()
        didSetup = false
    }

    // MARK: - Status / Playback

    private func checkPlayerReadiness() {
        guard let currentItem = player.currentItem else {
            hasError = true
            return
        }

        switch currentItem.status {
        case .readyToPlay:
            isReady = true
            hasError = false
            updatePlaybackState()
        case .failed:
            if let err = currentItem.error {
                print("❌ Player item failed: \(err.localizedDescription)")
            }
            hasError = true
        case .unknown:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.checkPlayerReadiness()
            }
        @unknown default:
            hasError = true
        }
    }

    private func updatePlaybackState() {
        guard isReady else { return }

        if isFocused && !isPaused {
            if isAtOrPastEnd() {
                seekToStartThenPlay()
            } else {
                player.volume = 0.0  // start muted
                player.play()
            }
        } else {
            player.volume = 0.0
            if isPaused { player.pause() }
        }
    }

    private func isAtOrPastEnd(tolerance: CMTime = CMTime(seconds: 0.25, preferredTimescale: 600)) -> Bool {
        guard let item = player.currentItem else { return false }
        let current = item.currentTime()
        let duration = item.duration
        guard duration.isNumeric && duration.seconds > 0 else { return false }
        return (duration - current) <= tolerance
    }

    private func seekToStartThenPlay() {
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if !self.isPaused && self.isFocused {
                self.player.volume = 0.0
                self.player.play()
            }
        }
    }

    // MARK: - Focus & Interaction

    private func handleFocusChange(_ focused: Bool) {
        updatePlaybackState()
    }

    private func togglePlayback() {
        guard isFocused else { return }
        isPaused.toggle()

        if isPaused {
            player.pause()
        } else {
            if isAtOrPastEnd() {
                seekToStartThenPlay()
            } else {
                player.volume = 0.0
                player.play()
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - View

    var body: some View {
        ZStack {
            // Video layer (full asset: no crop)
            SimpleVideoPlayerLayer(player: player)
                .opacity(isReady ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isReady)
                .onTapGesture { togglePlayback() }
                .onAppear { setupPlayer() }
                .onDisappear { cleanupPlayer() }

            // Loading overlay → bouncing logo
            if !isReady && !hasError {
                VStack(spacing: 12) {
                    BouncingLogo(size: 80, amplitude: 10, period: 0.9)
                }
                .padding(.top, 8)
            }

            // Error overlay
            if hasError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.yellow)
                    Text("Video Error")
                        .font(.headline)
                        .foregroundColor(.white)
                    Button("Retry") {
                        hasError = false
                        isReady = false
                        setupPlayer()
                    }
                    .foregroundColor(.blue)
                }
            }

            // Play button overlay when user-paused
            if isPaused && isReady && isFocused {
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 80, height: 80)
                        Image(systemName: "play.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: isFocused) { focused in
            handleFocusChange(focused)
        }
    }
}

// MARK: - Observer

final class VideoPlayerObserver: ObservableObject {
    private var timeObserver: Any?
    private var observingPlayer: AVQueuePlayer?
    private var itemStatusObserver: NSKeyValueObservation?
    private var currentItemObserver: NSKeyValueObservation?

    func startObserving(
        player: AVQueuePlayer,
        onItemChange: @escaping () -> Void,
        onStatusChange: @escaping (AVPlayerItem.Status) -> Void
    ) {
        stopObserving()
        observingPlayer = player

        // Observe currentItem changes and reattach status observer
        currentItemObserver = player.observe(\.currentItem, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                onItemChange()

                // Reattach to the new item's status
                self?.itemStatusObserver?.invalidate()
                self?.itemStatusObserver = nil
                if let newItem = player.currentItem {
                    self?.itemStatusObserver = newItem.observe(\.status, options: [.new]) { item, _ in
                        DispatchQueue.main.async { onStatusChange(item.status) }
                    }
                }
            }
        }

        // Attach to initial item if present
        if let item = player.currentItem {
            itemStatusObserver = item.observe(\.status, options: [.new]) { item, _ in
                DispatchQueue.main.async { onStatusChange(item.status) }
            }
        }

        // Keep a benign time observer (ensures periodic main-thread activity)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { _ in }
    }

    func stopObserving() {
        if let obs = timeObserver, let p = observingPlayer {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        currentItemObserver?.invalidate()
        currentItemObserver = nil
        observingPlayer = nil
    }

    deinit { stopObserving() }
}

// MARK: - SIMPLE AVPlayerLayer Host

struct SimpleVideoPlayerLayer: UIViewRepresentable {
    let player: AVQueuePlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.configure(with: player)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.configure(with: player)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { }
}

// MARK: - Custom UIView for AVPlayerLayer

class PlayerUIView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect   // << full asset, no crop
        playerLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(playerLayer)
    }

    func configure(with player: AVQueuePlayer) {
        playerLayer.player = player
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - Bouncing Logo (time-driven, resilient)

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
