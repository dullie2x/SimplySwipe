//
//  EndofGallery.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 7/13/25.
//

import SwiftUI
import Photos
import AVKit

struct EndOfGalleryView: View {
    let totalCount: Int
    let seenCount: Int
    let onRestart: () -> Void
    let onGoHome: () -> Void
    let onReset: (() -> Void)? // New reset callback
    let albumTitle: String? // For display in confirmation
    
    @State private var showingResetConfirmation = false
    
    // Initialize with reset functionality
    init(
        totalCount: Int,
        seenCount: Int,
        onRestart: @escaping () -> Void,
        onGoHome: @escaping () -> Void,
        onReset: (() -> Void)? = nil,
        albumTitle: String? = nil
    ) {
        self.totalCount = totalCount
        self.seenCount = seenCount
        self.onRestart = onRestart
        self.onGoHome = onGoHome
        self.onReset = onReset
        self.albumTitle = albumTitle
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Completion Icon
                    Image("orca7")
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(max(geometry.size.width * 0.35, 120), 200))
                        .accessibilityHidden(true)
                    
                    // Main message
                    VStack(spacing: 15) {
                        Text("Looks Like You're Done!")
                            .font(.custom(AppFont.regular, size: 32))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("You've reviewed all \(totalCount) photos and videos")
                            .font(.custom(AppFont.regular, size: 18))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    VStack(spacing: 16) {
                        // Reset Album button (only show if reset callback provided)
                        if onReset != nil {
                            Button(action: {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                                showingResetConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise.circle")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Reset Album")
                                        .font(.custom(AppFont.regular, size: 18))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.orange.opacity(0.8), Color.red.opacity(0.8)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                            }
                        }
                        
                        // Go to Home button
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            onGoHome()
                        }) {
                            HStack {
                                Image(systemName: "house")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Go to Home")
                                    .font(.custom(AppFont.regular, size: 16))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 50)
                }
            }
            .alert("Reset Album", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()
                    onReset?()
                }
            } message: {
                Text("This will bring back all photos and videos from \(albumTitle ?? "this album") and reset your progress to 0%. You can review them again from the beginning.")
            }
        }
    }
}
// MARK: - Preview
struct EndOfGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        EndOfGalleryView(
            totalCount: 1247,
            seenCount: 1247,
            onRestart: {},
            onGoHome: {},
            onReset: {},
            albumTitle: "Vacation 2024"
        )
    }
}
