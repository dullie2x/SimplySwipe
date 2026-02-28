//
//  VertScrollComponents.swift
//  Media App
//
//  Created on [Date]
//

import SwiftUI
import Photos
import AVKit

// MARK: - Media Loading View (renamed to avoid conflict)

struct MediaLoadingView: View {
    let progress: Double
    @State private var bounce = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Bouncing logo
                Image("orca8")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .offset(y: bounce ? -10 : 10)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true),
                        value: bounce
                    )
            }
        }
        .onAppear {
            bounce = true
        }
    }
}


// MARK: - Empty State View
struct EmptyStateView: View {
    let onReset: (() -> Void)?
    let filterDisplayName: String?
    @State private var showingResetConfirmation = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea(.all)
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Image("orca8")
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(max(geometry.size.width * 0.35, 120), 200))
                            .accessibilityHidden(true)
                        
                        Text("Looks Like You're Done")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("All device media have been reviewed")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Reset button (only show if reset callback provided)
                    if onReset != nil {
                        Button(action: {
                            showingResetConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Reset All Progress")
                                    .font(.custom(AppFont.regular, size: 18))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                        }
                        .padding(.horizontal, 40)
                    }
                    
                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .alert("Reset All Progress", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                onReset?()
            }
        } message: {
            Text("This will reset ALL of your app progress")
        }
    }
}
// MARK: - Individual Media Card Container
struct MediaCardContainer: View {
    let asset: PHAsset
    let index: Int
    @ObservedObject var viewModel: VertScrollViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        let cardSize = CGSize(width: geometry.size.width, height: geometry.size.height)
        let cardOffset = calculateOffset()
        let cardOpacity = calculateOpacity()
        let rotationAngle = calculateRotation()
        
        let isFocused = index == viewModel.previewIndex

        return MediaCardView(
            asset: asset,
            size: cardSize,
            offset: createOffsetValue(),
            onSwiped: { _ in },
            player: viewModel.getPlayer(for: index),
            highQualityImage: viewModel.getHighQualityImage(for: index),
            lowQualityImage: viewModel.getLowQualityImage(for: index),
            isCurrentlyFocused: isFocused,
            zoomScale: isFocused ? viewModel.zoomScale : 1.0,
            zoomOffset: isFocused ? viewModel.zoomOffset : .zero
        )
        .frame(width: cardSize.width, height: cardSize.height)
        .clipped()
        // Window-level pinch installer: only active for the focused card.
        // Lives on the UIWindow so it never interferes with SwiftUI's DragGesture.
        .background(
            WindowPinchInstaller(
                isActive: isFocused,
                onBegan: { viewModel.handleWindowPinchBegan() },
                onChanged: { deltaScale, centroid, centroidDelta in
                    viewModel.handleWindowPinchChanged(
                        deltaScale: deltaScale,
                        centroid: centroid,
                        centroidDelta: centroidDelta,
                        cardSize: cardSize
                    )
                },
                onEnded: { viewModel.handleWindowPinchEnded() }
            )
        )
        .offset(cardOffset)
        .rotationEffect(.degrees(rotationAngle))
        .opacity(cardOpacity)
        .zIndex(Double(viewModel.paginatedMediaItems.count - index))
        // IMPORTANT: do NOT tie .id to the index; keep it stable per asset only
        .id(asset.localIdentifier)
    }
    
    private func createOffsetValue() -> CGSize {
        if index == viewModel.previewIndex {
            return CGSize(width: viewModel.horizontalOffset, height: 0)
        } else {
            return .zero
        }
    }
    
    private func calculateOffset() -> CGSize {
        let xOffset = index == viewModel.previewIndex ? viewModel.horizontalOffset : 0
        let yOffset = CGFloat(index - viewModel.previewIndex) * geometry.size.height + viewModel.dragOffset
        return CGSize(width: xOffset, height: yOffset)
    }
    
    private func calculateOpacity() -> Double {
        let indexDiff = index - viewModel.previewIndex
        
        if index == viewModel.previewIndex {
            return max(0.3, 1.0 - abs(viewModel.horizontalOffset) / geometry.size.width)
        } else if abs(indexDiff) <= 1 {
            return 0.3
        } else {
            return 0.0
        }
    }
    
    private func calculateRotation() -> Double {
        return index == viewModel.previewIndex ? Double(viewModel.horizontalOffset / 5) : 0
    }
}

// MARK: - Main Content View (FIXED GESTURE HANDLING)
struct MainContentView: View {
    @ObservedObject var viewModel: VertScrollViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        let canSwipe = viewModel.swipeData.isPremium || viewModel.swipeData.remainingSwipes() > 0

        mediaCardsStack
            .clipped()
            .gesture(createDragGesture(canSwipe: canSwipe))
    }

    private var mediaCardsStack: some View {
        ZStack {
            // Use stable identity per asset to avoid tearing down views when indexes shift
            ForEach(Array(viewModel.paginatedMediaItems.enumerated()), id: \.element.localIdentifier) { index, asset in
                MediaCardContainer(
                    asset: asset,
                    index: index,
                    viewModel: viewModel,
                    geometry: geometry
                )
            }
        }
    }

    private func createDragGesture(canSwipe: Bool) -> some Gesture {
        DragGesture()
            .onChanged { value in
                viewModel.handleDragChanged(value: value, geometry: geometry, canSwipe: canSwipe)
            }
            .onEnded { value in
                viewModel.handleDragEnded(
                    value: value,
                    geometry: geometry,
                    canSwipe: viewModel.swipeData.remainingSwipes() > 0 || viewModel.swipeData.isPremium
                )
            }
    }

}


// MARK: - Window-Level Pinch Installer
// Attaches a UIPinchGestureRecognizer to the UIWindow, completely outside the SwiftUI
// view hierarchy. This means SwiftUI's DragGesture never sees a competing UIKit view
// in its hit-test path — swipes, labels, and animations all work normally.

struct WindowPinchInstaller: UIViewRepresentable {
    let isActive: Bool
    let onBegan: () -> Void
    let onChanged: (_ deltaScale: CGFloat, _ centroid: CGPoint, _ centroidDelta: CGPoint) -> Void
    let onEnded: () -> Void

    func makeUIView(context: Context) -> PinchInstallerView {
        let view = PinchInstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PinchInstallerView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.isActive = isActive

        if isActive, let window = uiView.window {
            context.coordinator.installRecognizer(on: window)
        } else if !isActive {
            context.coordinator.removeRecognizer()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isActive: Bool = false
        var onBegan: () -> Void
        var onChanged: (_ deltaScale: CGFloat, _ centroid: CGPoint, _ centroidDelta: CGPoint) -> Void
        var onEnded: () -> Void

        private var recognizer: UIPinchGestureRecognizer?
        private var lastCentroid: CGPoint = .zero

        init(
            onBegan: @escaping () -> Void,
            onChanged: @escaping (_ deltaScale: CGFloat, _ centroid: CGPoint, _ centroidDelta: CGPoint) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        deinit { removeRecognizer() }

        func installRecognizer(on window: UIWindow) {
            guard recognizer == nil else { return }
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = false
            pinch.delegate = self
            window.addGestureRecognizer(pinch)
            recognizer = pinch
        }

        func removeRecognizer() {
            if let r = recognizer {
                r.view?.removeGestureRecognizer(r)
                recognizer = nil
            }
        }

        // Allow the pinch to fire alongside SwiftUI's internal gesture recognizers
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view else { return }
            let centroid = gesture.location(in: view)

            switch gesture.state {
            case .began:
                lastCentroid = centroid
                gesture.scale = 1.0
                onBegan()

            case .changed:
                let deltaScale = gesture.scale
                gesture.scale = 1.0
                let centroidDelta = CGPoint(
                    x: centroid.x - lastCentroid.x,
                    y: centroid.y - lastCentroid.y
                )
                lastCentroid = centroid
                onChanged(deltaScale, centroid, centroidDelta)

            case .ended, .cancelled:
                onEnded()

            default:
                break
            }
        }
    }
}

/// Zero-size UIView that notifies the Coordinator when it enters/leaves the window,
/// so the gesture recognizer can be installed/removed at the right time.
class PinchInstallerView: UIView {
    weak var coordinator: WindowPinchInstaller.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window = window, coordinator?.isActive == true {
            coordinator?.installRecognizer(on: window)
        } else if window == nil {
            coordinator?.removeRecognizer()
        }
    }
}


// MARK: - Caption Overlay View
struct CaptionOverlayView: View {
    @ObservedObject var viewModel: VertScrollViewModel
    let currentAsset: PHAsset
    
    var body: some View {
        VStack {
            Spacer()
            
            if currentAsset.mediaType == .video {
                // For videos, pass mute state and toggle function
                Caption(
                    mediaSize: viewModel.mediaSize,
                    date: viewModel.mediaDate,
                    asset: currentAsset,
                    swipeDirection: viewModel.mediaTracker[currentAsset.localIdentifier]?.swipeDirection,
                    isMuted: viewModel.currentAssetMuted,
                    onMuteToggle: viewModel.toggleMute
                )
                .id(currentAsset.localIdentifier)
            } else {
                // For images, no mute controls
                Caption(
                    mediaSize: viewModel.mediaSize,
                    date: viewModel.mediaDate,
                    asset: currentAsset,
                    swipeDirection: viewModel.mediaTracker[currentAsset.localIdentifier]?.swipeDirection
                )
                .id(currentAsset.localIdentifier)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - End of Gallery Overlay View
struct EndOfGalleryOverlayView: View {
    @ObservedObject var viewModel: VertScrollViewModel
    
    var body: some View {
        if viewModel.showingEndOfGallery {
            EndOfGalleryView(
                totalCount: viewModel.totalMediaCount,
                seenCount: viewModel.seenMediaCount,
                onRestart: viewModel.restartGallery,
                onGoHome: viewModel.goToHome
            )
            .transition(.opacity)
            .zIndex(10)
        }
    }
}


