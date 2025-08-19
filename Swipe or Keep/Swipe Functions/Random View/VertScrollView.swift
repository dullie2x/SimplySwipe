//
//  VertScrollView.swift
//  Media App
//
//  Created on [Date]
//

import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct VertScroll: View {
    @StateObject private var viewModel = VertScrollViewModel()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            // Main content area
            if viewModel.isLoading {
                MediaLoadingView(progress: viewModel.loadingProgress)
            } else if viewModel.mediaItems.isEmpty {
                EmptyStateView()
            } else if !viewModel.showingEndOfGallery {
                GeometryReader { geometry in
                    MainContentView(viewModel: viewModel, geometry: geometry)
                }
                .background(Color.black)
                .ignoresSafeArea()
            }

            // Caption overlay
            if !viewModel.isLoading,
               !viewModel.showingEndOfGallery,
               let currentAsset = viewModel.safeCurrentAsset()
            {
                CaptionOverlayView(viewModel: viewModel, currentAsset: currentAsset)
            }

            // End of gallery overlay
            EndOfGalleryOverlayView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.fetchMedia()
        }
        // FIXED: Enhanced background/foreground handling with gesture reset
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
        // FIXED: Enhanced scene phase handling with gesture reset
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
                print("[VertScroll] previewIndex=\(newIndex) → assetID=\(currentAsset.localIdentifier)")
            }
        }
        // ADDITIONAL FIX: Handle device orientation changes that might mess up gesture state
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
    VertScroll()
}

// MARK: - iOS 15/16 Nav Bar Hiding Helper

extension View {
    @ViewBuilder
    func hideNavBarCompat() -> some View {
        if #available(iOS 16, *) {
            self.toolbar(.hidden, for: .navigationBar)
        } else {
            self.navigationBarHidden(true)
        }
    }
}
