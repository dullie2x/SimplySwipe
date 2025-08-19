//
//  FilteredVertScrollView.swift
//  Media App
//
//  Created on [Date]
//

import SwiftUI
import Photos
import AVKit
import AVFoundation
import UIKit

struct FilteredVertScroll: View {
    @StateObject private var viewModel: FilteredVertScrollViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationMode) var presentationMode
    
    init(filterOptions: PHFetchOptions) {
        self._viewModel = StateObject(wrappedValue: FilteredVertScrollViewModel(filterOptions: filterOptions))
    }
    
    var body: some View {
        ZStack {
            // Main content area
            if viewModel.isLoading {
                FilteredMediaLoadingView(progress: viewModel.loadingProgress)
            } else if viewModel.mediaItems.isEmpty {
                FilteredEmptyStateView()
            } else if !viewModel.showingEndOfGallery {
                GeometryReader { geometry in
                    FilteredMainContentView(viewModel: viewModel, geometry: geometry)
                }
                .background(Color.black)
                .ignoresSafeArea()
            }

            // Top navigation overlay
            if !viewModel.isLoading && !viewModel.showingEndOfGallery {
                FilteredTopNavigationView(viewModel: viewModel, presentationMode: presentationMode)
            }

            // Caption overlay
            if !viewModel.isLoading,
               !viewModel.showingEndOfGallery,
               let currentAsset = viewModel.safeCurrentAsset()
            {
                FilteredCaptionOverlayView(viewModel: viewModel, currentAsset: currentAsset)
            }

            // End of gallery overlay
            FilteredEndOfGalleryOverlayView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.fetchMedia()
        }
        // Enhanced background/foreground handling with gesture reset
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.handleAppWillEnterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.handleAppReturnFromBackground()
        }
        // Paywall changes may affect preload cadence
        .onReceive(NotificationCenter.default.publisher(for: .swipeCountChanged)) { _ in
            Task { @MainActor in
                viewModel.preloadContentForCurrentIndex()
            }
        }
        // Handle audio interruptions (phone call, Siri, etc.)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            guard let userInfo = note.userInfo,
                  let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
            switch type {
            case .began:
                // Reset gesture state during interruption
                viewModel.resetGestureState()
            case .ended:
                // Re-establish session and resume
                viewModel.handleAppReturnFromBackground()
            @unknown default:
                break
            }
        }
        // Memory pressure cleanup
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            viewModel.cleanupOldContent()
        }
        // Handle navigation to home from end of gallery
        .onReceive(NotificationCenter.default.publisher(for: .goHomeFromFiltered)) { _ in
            presentationMode.wrappedValue.dismiss()
            
            // After dismissing, navigate to main tab
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .navigateToMainTab, object: nil)
            }
        }
        // Enhanced scene phase handling with gesture reset
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // Single resume path through view model
                viewModel.handleAppReturnFromBackground()
            case .inactive:
                // Reset gesture state when going inactive (app switcher, etc.)
                viewModel.resetGestureState()
                viewModel.videoControlState.cleanup()
            case .background:
                // Ensure gesture state is clean when backgrounded
                viewModel.handleAppWillEnterBackground()
            @unknown default:
                break
            }
        }
        .fullScreenCover(isPresented: $viewModel.showPaywall) {
            PaywallMaxView()
        }
        .hideNavBarCompat()
        .onChange(of: viewModel.previewIndex) { newIndex in
            if let currentAsset = viewModel.safeCurrentAsset() {
                print("[FilteredVertScroll] previewIndex=\(newIndex) → assetID=\(currentAsset.localIdentifier)")
            }
        }
        // Handle device orientation changes that might mess up gesture state
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Small delay to let orientation settle, then reset any stuck gestures
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if viewModel.isDragging {
                    print("📱 Orientation changed during drag - resetting gesture state")
                    viewModel.resetGestureState()
                }
            }
        }
    }
}

#Preview {
    let options = PHFetchOptions()
    return FilteredVertScroll(filterOptions: options)
}
