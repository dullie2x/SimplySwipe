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
                Image("orca7")
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
                        Image("orca7")
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
        
        MediaCardView(
            asset: asset,
            size: cardSize,
            offset: createOffsetValue(),
            onSwiped: { _ in },
            player: viewModel.getPlayer(for: index),
            highQualityImage: viewModel.getHighQualityImage(for: index),
            lowQualityImage: viewModel.getLowQualityImage(for: index),
            isCurrentlyFocused: index == viewModel.previewIndex   // focus driven only by index
        )
        .frame(width: cardSize.width, height: cardSize.height)
        .clipped()
        .offset(cardOffset)
        .rotationEffect(.degrees(rotationAngle))
        .opacity(cardOpacity)
        .zIndex(Double(viewModel.paginatedMediaItems.count - index))
        .onTapGesture {
            if index == viewModel.previewIndex {
                viewModel.handleTap()
            }
        }
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
