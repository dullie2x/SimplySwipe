//
//  FilteredVertScrollComponents.swift
//  Media App
//
//  Created on [Date]
//

import SwiftUI
import Photos
import AVKit

// MARK: - Filtered Media Loading View

struct FilteredMediaLoadingView: View {
    let progress: Double
    @State private var bounce = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Just the bouncing logo
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let y = sin((2 * .pi / 0.9) * t) * 10
                
                Image("orca7")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .offset(y: y)
            }
        }
    }
}

// MARK: - Filtered Empty State View
struct FilteredEmptyStateView: View {
    var body: some View {
        VStack {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 70))
                .foregroundColor(.blue)
            
            Text("Nothing To Swipe Here")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.top, 20)
            
            Text("(Reset progress in settings)")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
    }
}

// MARK: - Top Navigation View
struct FilteredTopNavigationView: View {
    @ObservedObject var viewModel: FilteredVertScrollViewModel
    var presentationMode: Binding<PresentationMode>
    
    var body: some View {
        VStack {
            HStack {
                // Minimal back button
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "arrow.left.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.3))
                                .blur(radius: 10)
                        )
                        .contentShape(Circle())
                }
                .padding(.leading, 16)
                .padding(.top, 8)
                
                Spacer()
            }
            
            Spacer()
        }
    }
}

// MARK: - Individual Filtered Media Card Container
struct FilteredMediaCardContainer: View {
    let asset: PHAsset
    let index: Int
    @ObservedObject var viewModel: FilteredVertScrollViewModel
    let geometry: GeometryProxy
    
    var body: some View {
        let cardSize = CGSize(width: geometry.size.width, height: geometry.size.height)
        let cardOffset = calculateOffset()
        let cardOpacity = calculateOpacity()
        let rotationAngle = calculateRotation()
        
        FilteredMediaCardView(
            asset: asset,
            size: cardSize,
            offset: createOffsetValue(),
            onSwiped: { _ in },
            player: viewModel.getPlayer(for: index),
            highQualityImage: viewModel.getHighQualityImage(for: index),
            lowQualityImage: viewModel.getLowQualityImage(for: index),
            isCurrentlyFocused: index == viewModel.previewIndex,
            isMuted: $viewModel.currentAssetMuted
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
        // Stable ID per asset
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

// MARK: - Main Content View
struct FilteredMainContentView: View {
    @ObservedObject var viewModel: FilteredVertScrollViewModel
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
                FilteredMediaCardContainer(
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
                    canSwipe: viewModel.swipeData.remainingSwipes() > 0
                )
            }
    }
}

// MARK: - Caption Overlay View
struct FilteredCaptionOverlayView: View {
    @ObservedObject var viewModel: FilteredVertScrollViewModel
    let currentAsset: PHAsset
    
    var body: some View {
        VStack {
            Spacer()
            
            if currentAsset.mediaType == .video {
                // For videos, pass mute state and toggle function
                FilteredCaption(
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
                FilteredCaption(
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

// MARK: - Filtered End of Gallery Overlay View
struct FilteredEndOfGalleryOverlayView: View {
    @ObservedObject var viewModel: FilteredVertScrollViewModel
    
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
