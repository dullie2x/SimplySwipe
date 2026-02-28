import SwiftUI
import AVKit
import Photos

struct TikTokVideoPlayerView: View {
    let player: AVQueuePlayer
    let isFocused: Bool

    @State private var isPaused = false
    @State private var isReady = false
    @State private var hasError = false
    @State private var retryCount = 0
    @State private var focusDebounceTask: Task<Void, Never>? = nil
    @State private var isBuffering = false  // NEW: Track buffering state separately
    private let maxRetries = 3

    @StateObject private var playerObserver = VideoPlayerObserver()
    @StateObject private var bufferingCoordinator = VideoBufferingCoordinator()

    // MARK: - Setup / Teardown

    private func setupPlayer() {
        
        // CRITICAL: Check if player is already playing before doing anything else
        // This handles the case where the player is reused from cache
        if player.timeControlStatus == .playing || player.rate > 0 {
            isReady = true
            hasError = false
            isBuffering = false
            applyVolumeFromPreference()
            // Still observe for future changes
        }
        
        playerObserver.startObserving(
            player: player,
            onItemChange: {
                // Reset state for new item
                Task { @MainActor in
                    self.isReady = false
                    self.hasError = false
                    self.retryCount = 0
                    self.isBuffering = false
                    self.checkPlayerReadiness()
                }
            },
            onStatusChange: { status in
                Task { @MainActor in
                    self.handleStatusChange(status)
                }
            },
            onPlaybackStart: {
                // Called when player actually starts playing
                Task { @MainActor in
                    if !self.isReady {
                        self.isReady = true
                        self.hasError = false
                        self.isBuffering = false
                        self.applyVolumeFromPreference()
                    }
                }
            }
        )
        
        // Start monitoring buffering state
        startBufferingObservation()

        checkPlayerReadiness()
    }

    private func cleanupPlayer() {
        focusDebounceTask?.cancel()
        focusDebounceTask = nil
        playerObserver.stopObserving()
        stopBufferingObservation()
        player.pause()
    }
    
    // MARK: - Buffering Detection

    private func startBufferingObservation() {
        bufferingCoordinator.startObserving(player: player)
    }
    
    private func stopBufferingObservation() {
        bufferingCoordinator.stopObserving()
    }

    // MARK: - Status / Playback

    private func handleStatusChange(_ status: AVPlayerItem.Status) {
        
        switch status {
        case .readyToPlay:
            isReady = true
            hasError = false
            retryCount = 0
            applyVolumeFromPreference()
            updatePlaybackState()
            
        case .failed:
            // IMPORTANT: Check if player is actually playing before showing error
            // Sometimes video track fails but audio keeps playing
            if player.timeControlStatus == .playing || player.rate > 0 {
                isReady = true
                hasError = false
                applyVolumeFromPreference()
                return
            }
            
            if let item = player.currentItem, let error = item.error {
                let nsError = error as NSError
                
                // Ignore recoverable decoder errors (-12785 = kVTVideoDecoderMalfunctionErr)
                // These happen during rapid swiping and resolve on retry
                let isDecoderError = nsError.code == -12785
                let isNetworkError = nsError.domain == NSURLErrorDomain
                let isMediaServicesReset = nsError.code == AVError.Code.mediaServicesWereReset.rawValue
                
                let isRecoverable = isDecoderError || isNetworkError || isMediaServicesReset
                
                if isDecoderError {
                }
                
                if isRecoverable && retryCount < maxRetries {
                    retryCount += 1
                    
                    // Keep showing loading state, not error
                    isReady = false
                    hasError = false
                    
                    // Shorter delay for decoder errors since they resolve quickly
                    let delay = isDecoderError ? 0.3 : 1.0
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.checkPlayerReadiness()
                    }
                } else if !isRecoverable {
                    // Non-recoverable error - show immediately
                    hasError = true
                    isReady = false
                } else {
                    // Max retries reached
                    hasError = true
                    isReady = false
                }
            } else {
                // Unknown failure - give it one more chance
                if retryCount < maxRetries {
                    retryCount += 1
                    
                    isReady = false
                    hasError = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.checkPlayerReadiness()
                    }
                } else {
                    hasError = true
                    isReady = false
                }
            }
            
        case .unknown:
            // Check if player is actually playing despite unknown status
            if player.timeControlStatus == .playing || player.rate > 0 {
                isReady = true
                hasError = false
                applyVolumeFromPreference()
                return
            }
            
            // Don't show error for unknown state - just keep loading
            isReady = false
            hasError = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkPlayerReadiness()
            }
            
        @unknown default:
            // Don't immediately error - give it a chance
            if retryCount < 1 {
                retryCount += 1
                isReady = false
                hasError = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.checkPlayerReadiness()
                }
            } else {
                hasError = true
            }
        }
    }

    private func checkPlayerReadiness() {
        guard let currentItem = player.currentItem else {
            hasError = true
            return
        }

        // Check if player is actually playing (audio works even if video fails)
        if player.timeControlStatus == .playing || player.rate > 0 {
            isReady = true
            hasError = false
            return
        }

        handleStatusChange(currentItem.status)
    }

    private func applyVolumeFromPreference() {
        let shouldMute = VideoMutePreference.shared.isMuted
        player.volume = shouldMute ? 0.0 : 1.0
    }

    private func updatePlaybackState() {
        guard isReady else {
            return
        }

        if isFocused && !isPaused {
            if isAtOrPastEnd() {
                seekToStartThenPlay()
            } else {
                applyVolumeFromPreference()
                player.play()
            }
        } else {
            if isPaused {
                player.pause()
            } else {
                player.pause()
            }
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
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            if finished && !self.isPaused && self.isFocused {
                self.applyVolumeFromPreference()
                self.player.play()
            }
        }
    }

    // MARK: - Focus & Interaction

    private func handleFocusChange(_ focused: Bool) {
        // Cancel any pending focus change
        focusDebounceTask?.cancel()
        
        // Debounce focus changes to prevent decoder errors during rapid swiping
        focusDebounceTask = Task {
            // Small delay to let the player settle
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if focused {
                    applyVolumeFromPreference()
                }
                updatePlaybackState()
            }
        }
    }

    private func togglePlayback() {
        guard isFocused else {
            return
        }
        
        isPaused.toggle()

        if isPaused {
            player.pause()
        } else {
            if isAtOrPastEnd() {
                seekToStartThenPlay()
            } else {
                applyVolumeFromPreference()
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
                .animation(.easeInOut(duration: 0.3), value: isReady)
                .onTapGesture { togglePlayback() }
                .onAppear {
                    setupPlayer()
                }
                .onDisappear {
                    cleanupPlayer()
                }

            // Minimal buffering indicator (only when buffering, not initial load)
            if isReady && bufferingCoordinator.isBuffering && !hasError && isFocused {
                MinimalLoadingOverlay(
                    isLoading: true,
                    isSlow: false,
                    message: nil
                )
            }

            // Error overlay (only after genuine failures)
            if hasError {
                ZStack {
                    Color.black.opacity(0.7)
                    
                    VStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.yellow)
                            
                            VStack(spacing: 6) {
                                Text("Unable to Load Video")
                                    .font(.custom(AppFont.regular, size: 18))
                                    .foregroundColor(.white)
                                
                                Text("The video couldn't be loaded after \(maxRetries) attempts")
                                    .font(.custom(AppFont.regular, size: 14))
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            
                            Button(action: {
                                hasError = false
                                isReady = false
                                retryCount = 0
                                setupPlayer()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Try Again")
                                        .font(.custom(AppFont.regular, size: 16))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.9))
                        )
                        .padding(.horizontal, 40)
                        Spacer()
                    }
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
        .onChange(of: isFocused) { _, newValue in
            handleFocusChange(newValue)
        }
    }
}

// MARK: - Observer

final class VideoPlayerObserver: ObservableObject {
    private var timeObserver: Any?
    private var observingPlayer: AVQueuePlayer?
    private var itemStatusObserver: NSKeyValueObservation?
    private var currentItemObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var onPlaybackStartCallback: (() -> Void)?
    private var hasNotifiedPlaybackStart = false

    func startObserving(
        player: AVQueuePlayer,
        onItemChange: @escaping () -> Void,
        onStatusChange: @escaping (AVPlayerItem.Status) -> Void,
        onPlaybackStart: @escaping () -> Void = {}
    ) {
        stopObserving()
        observingPlayer = player
        onPlaybackStartCallback = onPlaybackStart
        hasNotifiedPlaybackStart = false

        // Observe currentItem changes and reattach status observer
        currentItemObserver = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.hasNotifiedPlaybackStart = false
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
        
        // Observe rate changes to detect when playback actually starts
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                if player.rate > 0 && !(self?.hasNotifiedPlaybackStart ?? true) {
                    self?.hasNotifiedPlaybackStart = true
                    self?.onPlaybackStartCallback?()
                }
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
        rateObserver?.invalidate()
        rateObserver = nil
        observingPlayer = nil
        onPlaybackStartCallback = nil
        hasNotifiedPlaybackStart = false
    }

    deinit { stopObserving() }
}

// MARK: - Buffering Coordinator

@MainActor
final class VideoBufferingCoordinator: ObservableObject {
    @Published var isBuffering = false

    private var bufferingObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?

    func startObserving(player: AVQueuePlayer) {
        stopObserving()

        bufferingObserver = player.currentItem?.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                let bufferEmpty = item.isPlaybackBufferEmpty
                let likelyToKeepUp = item.isPlaybackLikelyToKeepUp
                if bufferEmpty && !likelyToKeepUp {
                    self?.isBuffering = true
                } else if likelyToKeepUp {
                    self?.isBuffering = false
                }
            }
        }

        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    self?.isBuffering = true
                case .playing:
                    self?.isBuffering = false
                case .paused:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    func stopObserving() {
        bufferingObserver?.invalidate()
        bufferingObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
    }

    deinit { 
        // Access properties directly in deinit since it's synchronous
        bufferingObserver?.invalidate()
        timeControlObserver?.invalidate()
    }
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

