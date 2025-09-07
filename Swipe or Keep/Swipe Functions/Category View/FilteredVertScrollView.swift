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
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.scenePhase) private var scenePhase  // Add this line

    
    init(filterOptions: PHFetchOptions, filterType: FilterType) {
        self._viewModel = StateObject(wrappedValue: FilteredVertScrollViewModel(filterOptions: filterOptions, filterType: filterType))
    }
    
    var body: some View {
        ZStack {
            if viewModel.isLoading {
                FilteredMediaLoadingView(progress: viewModel.loadingProgress)
            } else if viewModel.mediaItems.isEmpty {
                FilteredEmptyStateView(
                    onReset: viewModel.currentFilterType != nil ? { viewModel.resetCurrentFilter() } : nil,
                    filterDisplayName: viewModel.filterDisplayName,
                    onBack: { presentationMode.wrappedValue.dismiss() }
                )
            } else if !viewModel.showingEndOfGallery {
                GeometryReader { geometry in
                    FilteredMainContentView(viewModel: viewModel, geometry: geometry)
                }
                .background(Color.black)
                .ignoresSafeArea()
            }
            
            // Top navigation overlay
            if !viewModel.isLoading && !viewModel.showingEndOfGallery && !viewModel.mediaItems.isEmpty {
                FilteredTopNavigationView(viewModel: viewModel, presentationMode: presentationMode)
            }
            
            // Caption overlay
            if !viewModel.isLoading,
               !viewModel.showingEndOfGallery,
               !viewModel.mediaItems.isEmpty,
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
          .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
              viewModel.handleAppWillEnterBackground()
          }
          .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
              viewModel.handleAppReturnFromBackground()
          }
          .onReceive(NotificationCenter.default.publisher(for: .swipeCountChanged)) { _ in
              DispatchQueue.main.async {
                  viewModel.preloadContentForCurrentIndex()
              }
          }
          .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
              guard let userInfo = note.userInfo,
                    let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
              switch type {
              case .began:
                  viewModel.resetGestureState()
              case .ended:
                  viewModel.handleAppReturnFromBackground()
              @unknown default:
                  break
              }
          }
          .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
              viewModel.cleanupOldContent()
          }
          .onReceive(NotificationCenter.default.publisher(for: .goHomeFromFiltered)) { _ in
              presentationMode.wrappedValue.dismiss()
              
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                  NotificationCenter.default.post(name: .navigateToMainTab, object: nil)
              }
          }
          .onChange(of: scenePhase) { _, phase in  // Updated syntax
              switch phase {
              case .active:
                  viewModel.handleAppReturnFromBackground()
              case .inactive:
                  viewModel.resetGestureState()
                  viewModel.videoControlState.cleanup()
              case .background:
                  viewModel.handleAppWillEnterBackground()
              @unknown default:
                  break
              }
          }
          .fullScreenCover(isPresented: $viewModel.showPaywall) {
              PaywallMaxView()
          }
          .hideNavBarCompat()
      }
  }


